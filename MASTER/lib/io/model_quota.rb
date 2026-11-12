# frozen_string_literal: true

require "date"
require "etc"
require "fileutils"
require "json"
require "time"
require_relative "atomic_write"

module Master
  module Io
    # Daily quota accounting for OpenRouter's shared free-model allowance and
    # hosted endpoints that declare per-lane caps. Local counts stay per slug
    # for diagnosis, but :free fallback/exhaustion sums them across the key.
    # QuotaCheck answers whether a paid provider has credit; ModelSkipCache
    # parks a model that just failed (test/test_model_skip_cache.rb).
    module ModelQuota
      extend self
      include ::Master::Io::AtomicWrite
      FREE_RE = /:free\z/.freeze
      DEFAULT_DAILY = 50
      OPENROUTER_LANE = "openrouter".freeze
      # One GET per key per half hour: the endpoint answers the key's own
      # remaining allowance, and the burn forecast stays the fallback, not a
      # second source polled on every call.
      PROVIDER_REFRESH_TTL_S = 1800

      @mutex = Mutex.new
      @refresh_mutex = Mutex.new
      @provider_refresh_mutex = Mutex.new
      @refresh_thread = nil

      module_function

      def daily_limit
        cfg = Master.models_config
        value = cfg&.dig("openrouter", "daily_quota_per_model")
        value.to_i.positive? ? value.to_i : DEFAULT_DAILY
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "model_quota.daily_limit", severity: :load_bearing)
        raise "model quota policy unreadable: #{e.class}: #{e.message}"
      end

      # Hosted free-tier endpoints (models.yml openai_compatible) declare their
      # own day cap beside the endpoint, as "<name>:<model>" lane ids: groq
      # 14,400/day, cerebras 100/day, the figures the endpoint blocks already
      # state. An endpoint without a positive daily_quota stays untracked rather
      # than guessed (TRUTHFUL_STATUS); a :free slug always answers daily_limit.
      def hosted_name(model)
        id = model.to_s
        name = id.split(":", 2).first
        return unless id.include?(":") && !name.to_s.empty?

        spec = Master.models_config&.dig("openai_compatible", name)
        name if spec.is_a?(Hash) && spec["daily_quota"].to_i.positive?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "model_quota.hosted_name", model: model.to_s)
        nil
      end

      def daily_limit_for(model)
        name = hosted_name(model)
        return daily_limit unless name

        Master.models_config.dig("openai_compatible", name, "daily_quota").to_i
      end

      def trackable?(model) = FREE_RE.match?(model.to_s) || !hosted_name(model).nil?

      # The provider's own answer about this key's remaining free daily
      # requests, recorded under "provider" in the state file for today. A
      # missing or stale reading answers nil and the burn forecast stands
      # (TRUTHFUL_STATUS: a forecast is a forecast, a reading is a reading).
      # OpenRouter returns { used:, limit:, remaining: }, not a scalar.
      # Reject incomplete or fractional samples; an absent reading is not zero.
      def normalize_provider_reading(value)
        return unless value.is_a?(Hash)

        reading = %w[used limit remaining].to_h do |key|
          number = value[key]
          return unless number.is_a?(Numeric) && number.finite? && number.to_i == number && number >= 0

          [key, number.to_i]
        end
        return if reading["used"] > reading["limit"] || reading["remaining"] > reading["limit"]

        reading
      rescue NoMethodError, TypeError
        nil
      end

      def provider_remaining(model, day: today_key, now: Time.now.utc)
        return unless FREE_RE.match?(model.to_s)

        reading = provider_quota_snapshot(day:, now:)
        reading[:remaining] if reading && reading[:fresh]
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.provider_remaining", model: model.to_s)
        nil
      end

      # Retain stale samples for display, but never use them for routing. The
      # observed remaining count is adjusted for this checkout's later calls.
      def provider_quota_snapshot(day: today_key, now: Time.now.utc)
        row = load_data.dig("provider", OPENROUTER_LANE)
        return unless row.is_a?(Hash) && row["day"] == day

        value = row["free_model_daily_requests"]
        reading = if value.is_a?(Hash)
                    normalize_provider_reading(value)
                  elsif value.is_a?(Numeric) && value >= 0
                    { "remaining" => value.to_i }
                  end
        return unless reading && row["fetched_at"].is_a?(Numeric)

        fetched_at = row["fetched_at"].to_f
        age = now.to_f - fetched_at
        return if age.negative?

        local_delta = [free_model_request_count(day:) - row["local_used_at_fetch"].to_i, 0].max
        {
          used: reading["used"] && reading["used"] + local_delta,
          limit: reading["limit"],
          remaining: [reading["remaining"].to_i - local_delta, 0].max,
          reported_remaining: reading["remaining"],
          local_requests_since_read: local_delta,
          source: age < PROVIDER_REFRESH_TTL_S ? "provider" : "stale_provider",
          fetched_at: Time.at(fetched_at).utc.iso8601,
          age_seconds: age.to_i,
          fresh: age < PROVIDER_REFRESH_TTL_S,
        }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.provider_quota_snapshot")
        nil
      end

      def free_model_request_count(day: today_key)
        data = load_data[day] || {}
        data.sum { |model, used| FREE_RE.match?(model.to_s) ? used.to_i : 0 }
      end

      def free_model_burn_rate_per_day(now: Time.now.utc, day: now.utc.strftime("%Y-%m-%d"))
        used = free_model_request_count(day:)
        date = Date.strptime(day, "%Y-%m-%d")
        start = Time.utc(date.year, date.month, date.day)
        elapsed = [now.to_f - start.to_f, 300.0].max
        used.zero? ? 0.0 : used.to_f * 86_400 / elapsed
      rescue ArgumentError
        0.0
      end

      # Read GET /api/v1/key with this checkout's active OpenRouter key and
      # store the answer's free_model_daily_requests as today's authoritative
      # remaining. Called from record() - the one funnel every successful free
      # call passes - and so never from a read path; record() schedules the
      # bounded worker and the TTL keeps it one GET per half hour. Every failure
      # is a word, never a raised error: quota
      # bookkeeping must not break the call that fed it.
      def refresh_from_provider!(now: Time.now.utc, day: today_key)
        key = active_openrouter_key
        return :no_key unless key
        return :in_flight unless @provider_refresh_mutex.try_lock

        begin
          return :fresh if provider_reading_fresh?(day:, now:)

          # Network I/O stays outside the accounting mutex and state flock.
          # Local requests keep counting while the provider is slow or down.
          reading = fetch_free_model_daily_requests(key)
          return :unreadable unless reading.is_a?(Hash)

          @mutex.synchronize do
            with_state_lock do
              data = load_data
              row = data.dig("provider", OPENROUTER_LANE)
              return :fresh if fresh_provider_row?(row, day:, now:)

              # Count from before the request. Calls made while it is in flight
              # are subtracted as local delta: conservative, never overstated.
              local_used = data.fetch(day, {}).sum do |model, used|
                FREE_RE.match?(model.to_s) ? used.to_i : 0
              end
              data["provider"] ||= {}
              data["provider"][OPENROUTER_LANE] = {
                "day" => day,
                "free_model_daily_requests" => reading,
                "local_used_at_fetch" => local_used,
                "fetched_at" => now.to_f,
              }
              save_data(data)
            end
          end
          :refreshed
        ensure
          @provider_refresh_mutex.unlock
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.refresh_from_provider!")
        :failed
      end

      # Schedule a single one-shot worker, replacing it only after completion.
      # A slow provider therefore cannot create an unbounded thread pool.
      def schedule_provider_refresh!(now: Time.now.utc, day: today_key)
        return :no_key unless active_openrouter_key
        return :fresh if provider_reading_fresh?(day:, now:)

        @refresh_mutex.synchronize do
          return :in_flight if @refresh_thread&.alive? || @provider_refresh_mutex.locked?

          @refresh_thread = Thread.new { refresh_from_provider!(now:, day:) }
          @refresh_thread.report_on_exception = false
        end
        :scheduled
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.schedule_provider_refresh!")
        :failed
      end

      def provider_reading_fresh?(day:, now:)
        @mutex.synchronize do
          with_state_lock do
            fresh_provider_row?(load_data.dig("provider", OPENROUTER_LANE), day:, now:)
          end
        end
      end

      def fresh_provider_row?(row, day:, now:)
        row.is_a?(Hash) && row["day"] == day &&
          row["fetched_at"].to_f > now.to_f - PROVIDER_REFRESH_TTL_S
      end

      # The key this checkout rides: the rotator's active key first, then the
      # first named environment key with a value. The value never leaves this
      # module.
      def active_openrouter_key
        Io::KeyRotator.active_key_for(OPENROUTER_LANE) ||
          Array(Master.models_config&.dig("openrouter", "keys_env"))
            .filter_map { |name| ENV[name] unless name.to_s.empty? }
            .find { |value| !value.to_s.strip.empty? }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.active_openrouter_key")
        nil
      end

      # The key never lands in an error message or a log; only the status
      # leaves this method.
      def fetch_free_model_daily_requests(key)
        require "net/http"
        uri = URI("https://openrouter.ai/api/v1/key")
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 8) do |http|
          http.get(uri.request_uri, { "Authorization" => "Bearer "+key })
        end
        return unless response.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(response.body.to_s)
        data = parsed.is_a?(Hash) ? parsed["data"] : nil
        return unless data.is_a?(Hash)

        normalize_provider_reading(data["free_model_daily_requests"])
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.fetch_free_model_daily_requests")
        nil
      end

      def record(model)
        return unless trackable?(model)

        @mutex.synchronize do
          with_state_lock do
            data = load_data
            day = today_key
            data[day] ||= {}
            key = model.to_s
            data[day][key] = data[day].fetch(key, 0) + 1
            prune_old_days!(data, day)
            save_data(data)
          end
        end

        # record() runs after the successful provider response. Count locally
        # before sampling the provider so that request is not subtracted twice.
        schedule_provider_refresh! if FREE_RE.match?(model.to_s) && ENV["MASTER_NO_QUOTA_REFRESH"] != "1"
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "model_quota.record", model: model.to_s)
        raise "model quota accounting failed: #{e.class}: #{e.message}"
      end

      def count(model, day: today_key)
        load_data.dig(day, model.to_s).to_i
      end

      def over_quota?(model, day: today_key, now: Time.now.utc)
        return false unless trackable?(model)

        authoritative = provider_remaining(model, day:, now:)
        return authoritative.zero? unless authoritative.nil?

        used = FREE_RE.match?(model.to_s) ? free_model_request_count(day:) : count(model, day:)
        used >= daily_limit_for(model)
      end

      # The provider's own remaining answer when one is fresh for today; the
      # computed limit-minus-count otherwise. A reading and a forecast never
      # mix in one number.
      def remaining(model, day: today_key, now: Time.now.utc)
        return unless trackable?(model)

        authoritative = provider_remaining(model, day:, now:)
        return authoritative unless authoritative.nil?

        used = FREE_RE.match?(model.to_s) ? free_model_request_count(day:) : count(model, day:)
        [daily_limit_for(model) - used, 0].max
      end

      def burn_rate_per_day(model, now: Time.now.utc, day: now.utc.strftime("%Y-%m-%d"))
        used = count(model, day:)
        date = Date.strptime(day, "%Y-%m-%d")
        start = Time.utc(date.year, date.month, date.day)
        elapsed = [now.to_f - start.to_f, 300.0].max
        return 0.0 if used.zero?

        used.to_f * 86_400 / elapsed
      rescue ArgumentError
        0.0
      end

      def forecast(model, now: Time.now.utc, day: now.utc.strftime("%Y-%m-%d"))
        return unless trackable?(model)

        provider = FREE_RE.match?(model.to_s) ? provider_quota_snapshot(day:, now:) : nil
        if provider && provider[:fresh]
          # OpenRouter's counter is shared by all free model slugs on the key.
          # Keep its global usage and limit together; never combine a global
          # remaining count with a single model's local count or configured cap.
          used = provider[:used] || free_model_request_count(day:)
          limit = provider[:limit] || daily_limit
          remaining = provider[:remaining]
          projected_daily = free_model_burn_rate_per_day(day:, now:)
          remaining_source = "provider"
        else
          if FREE_RE.match?(model.to_s)
            # OpenRouter's free-model cap belongs to the API key, not each slug.
            used = free_model_request_count(day:)
            limit = daily_limit
            projected_daily = free_model_burn_rate_per_day(day:, now:)
          else
            used = count(model, day:)
            limit = daily_limit_for(model)
            projected_daily = burn_rate_per_day(model, day:, now:)
          end
          remaining = [limit - used, 0].max
          remaining_source = "burn_forecast"
        end
        exhaustion_hours =
          if remaining.zero?
            0.0
          elsif projected_daily.positive?
            remaining.to_f / (projected_daily / 24.0)
          end

        {
          model: model.to_s,
          day:,
          used:,
          limit:,
          remaining:,
          remaining_source:,
          projected_daily: projected_daily.round(2),
          exhaustion_hours: exhaustion_hours&.round(2),
        }
      end

      def burn_risk?(model, threshold: 0.8, day: today_key, now: Time.now.utc)
        forecasted = forecast(model, day:, now:)
        return false unless forecasted

        forecasted[:projected_daily] >= forecasted[:limit] * threshold
      end

      def exhausted_models(day: today_key, now: Time.now.utc)
        data = load_data[day] || {}
        data.keys.select { |model| trackable?(model) && over_quota?(model, day:, now:) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.exhausted_models")
        raise "model quota state unreadable: #{e.class}: #{e.message}"
      end

      def snapshot(day: today_key, now: Time.now.utc)
        data = load_data[day] || {}
        tracked = data.select { |model, _| trackable?(model) }
        forecasts = tracked.keys.to_h { |model| [model, forecast(model, day:, now:)] }
        {
          day:,
          # The default (:free) limit; per-model limits ride in the forecasts.
          limit: daily_limit,
          models: tracked.transform_values(&:to_i),
          exhausted: forecasts.filter_map { |model, item| model if item && item[:remaining].to_i.zero? },
          forecasts:,
          provider: provider_quota_snapshot(day:, now:),
        }
      end

      # Process-local Mutex protects threads; the sidecar flock protects the
      # read-modify-write transaction across independent MASTER processes.
      def with_state_lock
        expanded = File.expand_path(path)
        directory = verified_atomic_directory(File.dirname(expanded))
        destination = File.join(directory, File.basename(expanded))

        FileUtils.mkdir_p(directory, mode: 0o700)
        directory_stat = File.lstat(directory)
        unless directory_stat.directory? && !directory_stat.symlink? &&
               (directory_stat.mode & 0o022).zero? &&
               verified_atomic_directory(directory) == directory
          raise IOError, "model quota directory must be a stable, real, non-writable-by-group/world directory"
        end

        lock_path = "#{destination}.lock"
        raise IOError, "refusing symlinked model quota lock" if File.symlink?(lock_path)
        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(lock_path, flags, 0o600) do |file|
          opened = file.stat
          unless opened.file? && opened.nlink == 1 && (opened.mode & 0o077).zero?
            raise IOError, "model quota lock must be a private singly linked regular file"
          end

          current = File.lstat(lock_path)
          unless current.file? && !current.symlink? && current.nlink == 1 &&
                 current.dev == opened.dev && current.ino == opened.ino
            raise IOError, "model quota lock path changed while opening"
          end
          raise IOError, "could not acquire model quota lock" unless file.flock(File::LOCK_EX)

          begin
            current = File.lstat(lock_path)
            unless current.file? && !current.symlink? && current.nlink == 1 &&
                   current.dev == opened.dev && current.ino == opened.ino
              raise IOError, "model quota lock path changed while waiting for its lock"
            end
            yield
          ensure
            file.flock(File::LOCK_UN)
          end
        end
      rescue SystemCallError => e
        raise IOError, "cannot safely lock model quota state: #{e.class}: #{e.message}"
      end

      # One private directory per OS user inside .master. On vm23 .master is a
      # group-shared 0770 directory (dev deploys, the master service runs),
      # which the private-directory check rightly refuses; a quota-<user>
      # directory created 0700 keeps each count private without loosening it.
      def path
        ENV["MASTER_MODEL_QUOTA_PATH"] || File.join(Master::ROOT, ".master", "quota-#{owner_name}", "model_quota.json")
      end

      def owner_name
        Etc.getpwuid(Process.uid)&.name || Process.uid.to_s
      rescue ArgumentError
        Process.uid.to_s
      end

      def today_key = Time.now.utc.strftime("%Y-%m-%d")

      def load_data
        expanded = File.expand_path(path)
        directory = verified_atomic_directory(File.dirname(expanded))
        state_path = File.join(directory, File.basename(expanded))
        return {} unless File.exist?(directory) || File.symlink?(directory)

        directory_stat = File.lstat(directory)
        unless directory_stat.directory? && !directory_stat.symlink? &&
               (directory_stat.mode & 0o022).zero? &&
               verified_atomic_directory(directory) == directory
          raise IOError, "model quota directory must be a stable, real, non-writable-by-group/world directory"
        end
        return {} unless File.exist?(state_path) || File.symlink?(state_path)

        before = File.lstat(state_path)
        unless before.file? && !before.symlink? && before.nlink == 1
          raise IOError, "model quota state must be a singly linked regular file"
        end
        if (before.mode & 0o077).positive?
          raise IOError, "model quota state permissions must be private (0600 or stricter)"
        end

        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(state_path, flags) do |file|
          opened = file.stat
          current = File.lstat(state_path)
          unless current.file? && !current.symlink? && current.nlink == 1 &&
                 current.dev == opened.dev && current.ino == opened.ino
            raise IOError, "model quota state path changed while opening"
          end

          raw = file.read
          after = File.lstat(state_path)
          unless after.file? && !after.symlink? && after.nlink == 1 &&
                 after.dev == opened.dev && after.ino == opened.ino &&
                 after.size == opened.size && after.mtime == opened.mtime && after.ctime == opened.ctime
            raise IOError, "model quota state changed while reading"
          end
          JSON.parse(raw)
        end
      rescue Errno::EACCES => e
        # The daemon writes this file owner-only, and a deploy boot check may run
        # as another user. That diagnostic reader cannot enforce the daemon's
        # quota, so preserve the documented empty-view behavior for EACCES only.
        Master::Ground::Swallow.log(e, context: "ModelQuota.load_data")
        {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.load_data")
        raise "model quota state unreadable: #{e.class}: #{e.message}"
      end

      def save_data(data)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, JSON.pretty_generate(data) + "\n", fsync: false, fsync_dir: false, mode: 0o600)
      end

      def prune_old_days!(data, keep_day)
        cutoff = (Date.parse(keep_day) - 7).strftime("%Y-%m-%d")
        data.delete_if { |day, _| day < cutoff }
      end
    end
  end
end
