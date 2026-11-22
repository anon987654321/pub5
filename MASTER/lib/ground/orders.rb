# frozen_string_literal: true

require "open3"
require "digest"
require "json"
require "uri"
require "net/http"
require "fileutils"

module Master
  module Ground
    # The bodies of standing orders. StandingOrders owns the schedule and the
    # state in data/state.yml; an order whose command names a class here runs
    # that class, looked up through Orders::Registry.
    module Orders
      # Standing-order callables. Subclass and implement `call`. Returning a
      # Master::Result::Ok marks the order done; Result::Err marks it errored.
      class Base
        def initialize(container:)
          @container = container
        end

        def bus = @container[:bus]
        def root = @container[:root]
        def event = @container[:event]

        def call
          raise NotImplementedError, "#{self.class}#call not implemented"
        end
      end

      # After every source write, emit merge/rename targets — OpenBSD-flat, dense parameterized slugs.
      class AggressiveMerge < Base
        THIN_LINES = 45
        MAX_LIB_DEPTH = 4

        def call
          paths = mutation_paths
          candidates = paths.flat_map { |path| candidates_for(path) }
                            .uniq { |row| "#{row[:action]}:#{row[:from]}:#{row[:to]}" }
          candidates.each { |row| bus&.publish("aggressive_merge:candidate", **row) }
          bus&.publish("aggressive_merge:scan", count: candidates.size, paths: paths.size)
          Result.ok(candidates:, paths:)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        def mutation_paths
          tracker = Master::Trace::WriteTracker.current
          touched = Array(tracker&.paths).map { |path| expand_path(path) }.reject(&:empty?).uniq
          return touched if touched.any?

          event_path = @container[:event]&.dig(:path).to_s
          expanded = expand_path(event_path)
          if !expanded.empty? && File.exist?(expanded)
            return [expanded]
          elsif !expanded.empty?
            parent = File.dirname(expanded)
            return [parent] if File.directory?(parent)
          end

          lib = File.join(root, "lib")
          File.directory?(lib) ? [lib] : [root]
        end

        def expand_path(path)
          value = path.to_s.strip
          return "" if value.empty?

          full = File.expand_path(value, root)
          full.start_with?("#{root}/") ? full : ""
        rescue StandardError
          ""
        end

        def candidates_for(path)
          full = expand_path(path)
          return [] if full.empty?

          if File.file?(full)
            file_candidates(full) + directory_candidates(File.dirname(full))
          elsif File.directory?(full)
            directory_candidates(full)
          else
            []
          end
        end

        def file_candidates(path)
          rel = rel_path(path)
          return [] unless rel.end_with?(".rb")

          out = slug_candidates(rel, File.basename(path, ".rb"))
          lines = File.foreach(path).count
          if lines.positive? && lines <= THIN_LINES
            target = fold_target_for(path)
            out << action(:merge, rel, target, "thin file (#{lines} lines) - fold into parent") if target
          end

          if rel.start_with?("lib/") && rel.count("/") > MAX_LIB_DEPTH
            out << action(:flatten, rel, shallow_target(rel), "depth #{rel.count('/')} > #{MAX_LIB_DEPTH} - flatten toward lib/")
          end
          out.uniq { |row| "#{row[:action]}:#{row[:from]}:#{row[:to]}" }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "AggressiveMerge.file_candidates")
          []
        end

        def slug_candidates(rel, stem)
          ParameterizedSlug.issues_for_stem(stem).map do |issue|
            to_rel = issue.to == issue.from ? rel : rel.sub(/[^\/]+\.rb\z/, "#{issue.to}.rb")
            action(issue.action.to_sym, rel, to_rel, issue.reason)
          end
        end

        def directory_candidates(dir)
          return [] unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.rb")).flat_map { |file| file_candidates(file) }
        end

        def fold_target_for(path)
          dir = File.dirname(path)
          stem = File.basename(path, ".rb")
          return if ParameterizedSlug.fold_suffix?(stem)

          siblings = Dir.glob(File.join(dir, "*.rb")).reject { |entry| entry == path }
          parent = siblings.find { |entry| File.basename(entry, ".rb") == stem.split("_").first }
          rel_path(parent) if parent
        end

        def shallow_target(rel)
          parts = rel.split("/")
          return rel if parts.size <= MAX_LIB_DEPTH + 1

          ["lib", parts[-2], parts[-1]].join("/")
        end

        def action(kind, from, to, reason)
          { action: kind.to_s, from: from.to_s, to: to.to_s, reason: reason.to_s }
        end

        def rel_path(path)
          path.delete_prefix("#{root}/")
        end
      end

      # Weekly review of data/* shape misfit. Walks every yaml under data/, flags
      # files that grew past LINE_LIMIT (split candidate), files with overlapping
      # top-level keys (merge candidate), and emits suggestions to the bus.
      class ArchitectureAudit < Base
        LINE_LIMIT = 200

        def call
          data_dir = File.join(root, "data")
          bloated = bloated_files(data_dir)
          overlaps = overlapping_keys(data_dir)
          bus&.publish("architecture_audit:bloated", files: bloated)
          bus&.publish("architecture_audit:overlap", pairs: overlaps)
          Result.ok(bloated:, overlaps:)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        def bloated_files(dir)
          Dir.glob(File.join(dir, "*.yml")).filter_map do |f|
            lines = File.foreach(f).count
            [File.basename(f), lines] if lines > LINE_LIMIT
          end.sort_by { |_, n| -n }
        end

        def overlapping_keys(dir)
          files = Dir.glob(File.join(dir, "*.yml"))
          keys = files.each_with_object({}) do |f, h|
            document = begin
              Master.load_yaml(f)
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "architecture_audit.overlapping_keys", path: f)
              nil
            end
            h[File.basename(f)] = document.is_a?(Hash) ? document.keys : []
          end
          pairs = []
          keys.to_a.combination(2) do |(a, ka), (b, kb)|
            shared = ka & kb
            pairs << [a, b, shared] if shared.any?
          end
          pairs
        end
      end

      class Autocommit < Base
        def call
          repo = File.expand_path(File.join(root, ".."))
          paths = mutation_paths(repo)
          return Result.ok(skipped: true, reason: "no owned mutation paths") if paths.empty?

          relative = paths.map { |path| path.delete_prefix("#{repo}/") }.uniq
          out, _, status = Master::Io::Exec.capture3("git", "-C", repo, "status", "--porcelain", "--", *relative)
          return Result.ok(skipped: true) unless status.success? && !out.strip.empty?

          message = "auto: standing-order commit (#{out.lines.size} file(s))"
          commit(repo, message:, paths: relative) || push(repo, files: out.lines.size, paths: relative)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        def commit(repo, message:, paths:)
          Master::Io::GitOperations.new(repo).git!("commit", "-m", message, "--", *paths)
          nil
        rescue RuntimeError => e
          bus&.publish("autocommit:refused", error: e.message[0, 200], paths:)
          Result.err("commit failed: #{e.message}")
        end

        def push(repo, files:, paths:)
          push_out, push_st = Master::Io::Exec.capture2e("git", "-C", repo, "push")

          if push_st.success?
            bus&.publish("autocommit:pushed", files:, paths:)
            Result.ok(committed: true, pushed: true, paths:)
          else
            bus&.publish("autocommit:push_failed", error: push_out.strip[0, 200], paths:)
            Result.ok(committed: true, pushed: false, paths:, push_error: push_out.strip)
          end
        end

        def mutation_paths(repo)
          tracker = Master::Trace::WriteTracker.current
          touched = Array(tracker&.paths).filter_map { |path| owned_path(path, repo) }.uniq
          return touched if touched.any?

          [event&.dig(:path), event&.dig(:full)].filter_map { |path| owned_path(path, repo) }.uniq
        end

        def owned_path(path, repo)
          value = path.to_s.strip
          return if value.empty?

          full = File.expand_path(value, root)
          full.start_with?("#{repo}/") && File.file?(full) ? full : nil
        rescue StandardError
          nil
        end
      end

      class Backup < Base
        REMOTE_HOST = "s4vm23@wingman1.openbsd.amsterdam"
        REMOTE_PATH = "backup"
        SSH_OPTS = %w[-o BatchMode=yes -o ConnectTimeout=10].freeze

        def source_root = File.expand_path("..", root)

        def call
          src = source_root
          return Result.err("backup: #{src} is not a directory", category: :infrastructure) unless File.directory?(src)

          cmd = ["openrsync", "-ae", "ssh #{SSH_OPTS.join(" ")}",
                 src, "#{REMOTE_HOST}:#{REMOTE_PATH}"]
          out, status = Master::Io::Exec.capture2e(*cmd)
          if status.success?
            bus&.publish("backup:ok", src:)
            Result.ok("backup: synced #{File.basename(src)} -> #{REMOTE_HOST}")
          else
            bus&.publish("backup:error", error: out.lines.last.to_s.strip)
            Result.err("backup: #{out.lines.last.to_s.strip}", category: :infrastructure)
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Orders::Backup.call", event_bus: bus)
          Result.err(e.message, category: :infrastructure)
        end
      end

      class ConstitutionDrift < Base
        STATE_PATH = "runtime/constitution_drift.json"

        def call
          scanner = @container[:scanner]
          return Result.err("no scanner in container") unless scanner

          report = build_report(scanner)
          publish_drift(report)
          persist(report)
          Result.ok(report)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        def build_report(scanner)
          by_axiom = tally_violations(scanner)
          total = by_axiom.values.sum
          delta = total - load_previous[:total].to_i
          { total:, delta:, by_axiom:, worst: by_axiom.max_by { |_, n| n }&.first }
        end

        def lib_files
          Dir.glob(File.join(root, "lib", "**", "*.rb"))
             .reject { |p| p.include?("/knowledge/") || p.include?("/vendor/") }
             .sort
        end

        def tally_violations(scanner)
          lib_files.each_with_object(Hash.new(0)) do |path, acc|
            result = scanner.scan(path, depth: :deep)
            next unless result.ok?
            result.value!.each { |f| Array(f[:tags]).each { |t| acc[t.to_s] += 1 } }
          end
        end

        def publish_drift(report)
          delta = report[:delta]
          kind = if delta.negative?
                   "improved"
                 else
                   (delta.positive? ? "regressed" : "steady")
                 end
          bus&.publish("constitution_drift:#{kind}", **report)
        end

        def state_file = File.join(root, STATE_PATH)

        def load_previous
          return { total: 0 } unless File.exist?(state_file)

          JSON.parse(File.read(state_file), symbolize_names: true)
        rescue StandardError => e
          Swallow.log(e, context: "constitution_drift.load_previous", event_bus: bus)
          { total: 0 }
        end

        def persist(report)
          FileUtils.mkdir_p(File.dirname(state_file))
          record = report.slice(:total, :by_axiom).merge(at: Time.now.utc.iso8601)
          File.write(state_file, JSON.pretty_generate(record))
        rescue StandardError => e
          Swallow.log(e, context: "constitution_drift.persist", event_bus: bus)
        end
      end

      class AvailabilityPosture < Base
        def call
          router = @container[:agent]&.model_router
          return Result.err("availability: no model router") unless router.respond_to?(:pool)

          policy = Master::CLI::Routing::AvailabilityPolicy.new(root:)
          models = Array(router.pool(wait: false)).uniq
          levels = models.group_by { |model| policy.level_for(model) }.transform_values(&:size)
          floor = policy.ladder_floor(:interactive)
          reachable = models.any? { |model| policy.meets_floor?(model, operation: :interactive) }

          payload = {
            floor:,
            reachable:,
            degraded: !reachable,
            levels:,
            models: models.first(12),
          }
          bus&.publish("availability:posture", **payload)
          Result.ok(payload)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "availability_posture", event_bus: bus)
          Result.err(e.message, category: :infrastructure)
        end
      end

      class RestartMaster < Base
        def call
          _, status = Master::Io::Exec.capture2e("doas", "rcctl", "restart", "master")
          status.success? ? Result.ok(restarted: true) : Result.err("rcctl restart failed")
        rescue StandardError => e
          Result.err(e.message)
        end
      end

      # General-purpose public page scraper for StandingOrders.
      # Targets: data/scrape_targets.yml. Snapshots: .master/scrape/snapshots/.
      # GET-only through SsrfGuard. No credentials, cookies, or login flows.
      class PublicScrape < Base
        TARGETS_PATH = "data/scrape_targets.yml"
        SNAPSHOT_DIR = File.join(".master", "scrape", "snapshots")
        DEFAULT_MAX_BYTES = 200_000
        TIMEOUT_S = 20
        EXCERPT_CHARS = 400

        def call
          targets = load_targets
          return Result.ok(skipped: true, reason: "no targets in #{TARGETS_PATH}") if targets.empty?

          FileUtils.mkdir_p(snapshot_root)
          rows = targets.map { |target| scrape_one(target) }
          changed = rows.count { |r| r[:status] == "changed" || r[:status] == "new" }
          errors = rows.count { |r| r[:status] == "error" }

          bus&.publish("public_scrape:ran", targets: rows.size, changed:, errors:)
          summary = rows.map { |r| format_row(r) }.join("\n")
          Result.ok("public_scrape: #{rows.size} target(s), #{changed} changed, #{errors} error(s)\n#{summary}")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Orders::PublicScrape.call", event_bus: bus)
          Result.err(e.message)
        end

        private

        def load_targets
          path = File.join(root, TARGETS_PATH)
          return [] unless File.exist?(path)

          raw = Master.load_yaml(path)
          list = raw.is_a?(Hash) ? Array(raw["targets"]) : Array(raw)
          list.filter_map do |entry|
            next unless entry.is_a?(Hash)

            url = entry["url"].to_s.strip
            next if url.empty?

            {
              url: url,
              label: entry["label"].to_s.strip.empty? ? slug_for(url) : entry["label"].to_s.strip,
              max_bytes: Integer(entry["max_bytes"] || DEFAULT_MAX_BYTES),
            }
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "PublicScrape.load_targets")
          []
        end

        def scrape_one(target)
          uri = URI(target[:url])
          unless Master::Io::SsrfGuard.valid_http_uri?(uri)
            return row(target, "error", "refused: only public http(s) on standard ports")
          end

          request = Net::HTTP::Get.new(uri.request_uri)
          request["User-Agent"] = "MASTER-public-scrape/1.0"
          request["Accept"] = "text/html,application/xhtml+xml,application/xml,text/plain;q=0.9,*/*;q=0.8"

          response = Master::Io::SsrfGuard.request(
            uri, request,
            max_bytes: target[:max_bytes],
            timeout: TIMEOUT_S * 2,
            open_timeout: TIMEOUT_S,
            read_timeout: TIMEOUT_S,
            write_timeout: TIMEOUT_S
          )

          code = response.code.to_i
          unless code.between?(200, 299)
            return row(target, "error", "HTTP #{code}")
          end

          text = plain_text(response.body.to_s)
          fingerprint = Digest::SHA256.hexdigest(text)
          previous = read_snapshot(target[:label])

          status =
            if previous.nil?
              "new"
            elsif previous["fingerprint"] == fingerprint
              "unchanged"
            else
              "changed"
            end

          write_snapshot(target[:label], url: target[:url], fingerprint:, text:, status:, code:)
          excerpt = text[0, EXCERPT_CHARS].to_s.gsub(/\s+/, " ").strip
          row(target, status, excerpt.empty? ? "(empty body)" : excerpt)
        rescue Master::Io::SsrfGuard::ResponseTooLarge
          row(target, "error", "body exceeded byte cap")
        rescue SocketError, Timeout::Error, URI::InvalidURIError => e
          row(target, "error", e.message.to_s[0, 120])
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "PublicScrape.scrape_one", url: target[:url])
          row(target, "error", e.message.to_s[0, 120])
        end

        def plain_text(body)
          text = body.to_s.dup
          text.force_encoding("UTF-8")
          text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          text.gsub!(%r{<script\b[^>]*>.*?</script>}mi, " ")
          text.gsub!(%r{<style\b[^>]*>.*?</style>}mi, " ")
          text.gsub!(/<!--.*?-->/m, " ")
          text.gsub!(/<[^>]+>/, " ")
          text.gsub!(/&nbsp;/i, " ")
          text.gsub!(/&/i, "&")
          text.gsub!(/</i, "<")
          text.gsub!(/>/i, ">")
          text.gsub!(/"/i, "\"")
          text.gsub!(/&#\d+;/, " ")
          text.gsub!(/\s+/, " ")
          text.strip
        end

        def snapshot_root = File.join(root, SNAPSHOT_DIR)

        def snapshot_path(label)
          safe = label.to_s.gsub(/[^A-Za-z0-9._-]/, "-")[0, 80]
          safe = "target" if safe.empty?
          File.join(snapshot_root, "#{safe}.json")
        end

        def read_snapshot(label)
          path = snapshot_path(label)
          return unless File.exist?(path)

          JSON.parse(File.read(path))
        rescue StandardError
          nil
        end

        def write_snapshot(label, url:, fingerprint:, text:, status:, code:)
          path = snapshot_path(label)
          payload = {
            "url" => url,
            "label" => label,
            "fingerprint" => fingerprint,
            "status" => status,
            "http_code" => code,
            "chars" => text.bytesize,
            "excerpt" => text[0, EXCERPT_CHARS],
            "at" => Time.now.utc.iso8601,
          }
          File.write(path, JSON.pretty_generate(payload))
        end

        def row(target, status, detail)
          { label: target[:label], url: target[:url], status:, detail: detail.to_s }
        end

        def format_row(r)
          "#{r[:label]} [#{r[:status]}] #{r[:detail][0, 120]}"
        end

        def slug_for(url)
          host = URI(url).host.to_s.gsub(/[^A-Za-z0-9.-]/, "-")
          host.empty? ? "page" : host
        rescue StandardError
          "page"
        end
      end

      # Maps standing-order callable: keys to Order subclasses. Decouples the yaml
      # from class names — `callable: autocommit` is stable even if the class moves.
      module Registry
        def self.lookup(key)
          table[key.to_s]
        end

        def self.table
          @table ||= {
            "autocommit" => Autocommit,
            "restart_master" => RestartMaster,
            "architecture_audit" => ArchitectureAudit,
            "aggressive_merge" => AggressiveMerge,
            "constitution_drift" => ConstitutionDrift,
            "backup" => Backup,
            "availability_posture" => AvailabilityPosture,
            "public_scrape" => PublicScrape,
          }
        end

        def self.register(key, klass)
          table[key.to_s] = klass
        end
      end
    end
  end
end
