# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "tempfile"
require "fileutils"
require "uri"
require_relative "../ground/failure_taxonomy"
require_relative "../io/quota_check"
# model_exists?, cancel_prediction and cancel_training all rescue into
# Ground::Swallow, and nothing required it. Under a full MASTER boot something
# else had loaded it first; loaded standalone -- which is how MASTER/tools/replicate
# uses this file -- the rescue itself raised
# NameError. The three call sites where that lands are the ones you reach when
# something has already gone wrong.
require_relative "../ground/swallow"

module Master
  module Io
    # Thin Replicate predictions client — used by the replicate_kokoro TTS engine.
    class ReplicateClient
      # File upload/download helpers — separate from ReplicateClient's own
      # prediction/training/model-catalog API.
      module AssetTransfer
        def upload_file(path)
          mime = case File.extname(path).downcase
                 when ".jpg", ".jpeg" then "image/jpeg"
                 when ".png" then "image/png"
                 when ".webp" then "image/webp"
                 when ".gif" then "image/gif"
                 else
                   raise ArgumentError, "unsupported image type #{File.extname(path)}"
                 end
          upload_binary(path, mime:)
        end

        def upload_zip(path)
          upload_binary(path, mime: "application/zip")
        end

        # Stream under a byte and total-time cap. A failed download leaves the
        # previous artifact intact; rename is atomic because the temporary file
        # lives beside the destination.
        def download_url(url, path, max_bytes: MAX_DOWNLOAD_BYTES)
          uri = URI(url.to_s)
          raise ArgumentError, "refusing non-https download url" unless uri.is_a?(URI::HTTPS) && uri.port == 443
          raise ArgumentError, "refusing download URL credentials" unless uri.userinfo.nil?
          raise ArgumentError, "refusing download URL fragment" unless uri.fragment.nil?
          raise ArgumentError, "refusing download from untrusted host: #{uri.host}" unless uri.host.to_s.match?(ALLOWED_DOWNLOAD_HOST)

          max_bytes = Integer(max_bytes)
          raise ArgumentError, "download byte limit must be positive" unless max_bytes.positive?
          raise ArgumentError, "download byte limit exceeds #{MAX_DOWNLOAD_BYTES}" if max_bytes > MAX_DOWNLOAD_BYTES

          target = File.expand_path(path)
          directory = File.dirname(target)
          FileUtils.mkdir_p(directory)
          existing_target = begin
            File.lstat(target)
          rescue Errno::ENOENT
            nil
          end
          if existing_target && (!existing_target.file? || existing_target.symlink?)
            raise ArgumentError, "download target must be a regular non-symlink file"
          end
          mode = existing_target ? existing_target.mode & 0o7777 : 0o600
          deadline = monotonic_now + DOWNLOAD_TIMEOUT_SECONDS

          Tempfile.create(["replicate-download-", ".part"], directory, binmode: true) do |file|
            remaining = remaining_timeout(deadline, OPEN_TIMEOUT_SECONDS, label: "download")
            Net::HTTP.start(
              uri.host, uri.port, use_ssl: true,
              open_timeout: remaining,
              read_timeout: remaining_timeout(deadline, READ_TIMEOUT_SECONDS, label: "download"),
              write_timeout: WRITE_TIMEOUT_SECONDS
            ) do |http|
              http.request_get(uri.request_uri) do |response|
                raise "download failed #{response.code}" unless response.code.to_i.between?(200, 299)
                declared = response["content-length"].to_s
                if declared.match?(/\A\d+\z/) && declared.to_i > max_bytes
                  raise ArgumentError, "download over #{max_bytes} bytes"
                end

                write_capped(response, file, max_bytes, http:, deadline:)
              end
            end
            remaining_timeout(deadline, READ_TIMEOUT_SECONDS, label: "download finalization")

            file.flush
            file.fsync
            File.chmod(mode, file.path)
            file.close
            current_target = begin
              File.lstat(target)
            rescue Errno::ENOENT
              nil
            end
            if existing_target
              unless current_target && current_target.dev == existing_target.dev &&
                     current_target.ino == existing_target.ino
                raise IOError, "download target changed during transfer"
              end
            elsif current_target
              raise IOError, "download target appeared during transfer"
            end
            File.rename(file.path, target)
          end
          path
        end

        private

        def write_capped(response, file, max_bytes, http:, deadline:)
          written = 0
          response.read_body do |chunk|
            remaining = remaining_timeout(deadline, READ_TIMEOUT_SECONDS, label: "download")
            http.read_timeout = remaining
            written += chunk.bytesize
            raise ArgumentError, "download over #{max_bytes} bytes" if written > max_bytes

            offset = 0
            while offset < chunk.bytesize
              count = file.write(chunk.byteslice(offset..))
              raise IOError, "download wrote no bytes" unless count&.positive?

              offset += count
            end
          end
        end
      end
      # LoRA training lifecycle (ostris/flux-dev-lora-trainer): start, poll,
      # fetch weights. Grouped apart from prediction/model-management to keep
      # ReplicateClient itself under the NO_GOD_CLASS public-method ceiling --
      # same pattern as AssetTransfer. Methods run against the including
      # instance, so post/get/create_model/model_exists?/wait_for_training/
      # download_url (from AssetTransfer) all resolve normally.
      module Training
        # Start ostris/flux-dev-lora-trainer. photos_zip_url must be a public or
        # Replicate Files API URL. Returns the full training object when wait is
        # true; when wait is false (webhook / async), returns the create response.
        def train_lora(
          photos_zip_url,
          destination,
          trigger_word: "subjectxyz",
          timeout: 3600,
          steps: nil,
          lora_rank: nil,
          webhook: nil,
          webhook_events_filter: nil,
          wait: true,
          extra_input: {}
        )
          timeout = operation_timeout!(timeout, "training timeout")
          deadline = monotonic_now + timeout
          create_model(destination, deadline:) unless model_exists?(destination, deadline:)
          trainings_uri, body = build_training_request(
            photos_zip_url, destination, trigger_word:, steps:, lora_rank:, webhook:, webhook_events_filter:, extra_input:, deadline:
          )
          training = post(trainings_uri, body, deadline:)
          wait ? wait_for_training(training["id"], timeout:, deadline:) : training
        end

        def get_training(id, deadline: nil)
          get(URI("#{BASE}/trainings/#{id}"), deadline:)
        end

        def training_weights_url(training)
          training = get_training(training) if training.is_a?(String)
          output = training["output"]
          case output
          when Hash
            output["weights"] || output["version"]
          when String
            output
          end
        end

        private

        def build_training_request(photos_zip_url, destination, trigger_word:, steps:, lora_rank:, webhook:, webhook_events_filter:, extra_input:, deadline:)
          trainer_owner, trainer_name = LORA_TRAINER.split("/")
          trainer_version = latest_version(LORA_TRAINER, deadline:)
          trainings_uri = URI("#{BASE}/models/#{trainer_owner}/#{trainer_name}/versions/#{trainer_version}/trainings")

          input = {
            input_images: photos_zip_url,
            trigger_word:,
          }
          input[:steps] = steps if steps
          input[:lora_rank] = lora_rank if lora_rank
          input.merge!(extra_input) if extra_input && !extra_input.empty?

          body = { destination:, input: }
          body[:webhook] = webhook if webhook.to_s.strip != ""
          body[:webhook_events_filter] = Array(webhook_events_filter) if webhook_events_filter

          [trainings_uri, body]
        end
      end

      include AssetTransfer
      include Training

      # Raised when a bounded API or transfer deadline expires.
      DeadlineExceeded = Class.new(StandardError)
      ResponseTooLarge = Class.new(StandardError)
      # Raised for HTTP statuses worth a retry (rate limit, server-side fault).
      # A 4xx other than 429 means the request itself is wrong and retrying
      # retries repeat the same failure.
      TransientError = Class.new(StandardError)
      # A spend limit. The status codes alone could not tell this apart: a
      # 402 already fell through to the plain raise and was handled correctly
      # by accident, but Replicate also answers 429 when the account is out of
      # budget rather than merely too fast — and TRANSIENT_STATUS reads every
      # 429 as a throttle, so those were retried three times with backoff to
      # buy the same refusal three times. Named so the retry loop can tell a
      # wait that will help from one that cannot.
      ExhaustedError = Class.new(StandardError)

      CONFIG_PATH = File.expand_path("~/.config/replicate/config.json").freeze
      MAX_TOKEN_FILE_BYTES = 256 * 1024
      BASE = "https://api.replicate.com/v1"
      API_HOST = "api.replicate.com"
      OPEN_TIMEOUT_SECONDS = 10
      READ_TIMEOUT_SECONDS = 120
      MAX_MODEL_PAGES = 1_000
      LORA_TRAINER = "ostris/flux-dev-lora-trainer"
      TRANSIENT_STATUS = ((500..599).to_a << 429).freeze
      MAX_DOWNLOAD_BYTES = 4 * 1024**3
      MAX_UPLOAD_BYTES = 4 * 1024**3
      MAX_RESPONSE_BYTES = 16 * 1024**2
      WRITE_TIMEOUT_SECONDS = 120
      REQUEST_TIMEOUT_SECONDS = 300
      DOWNLOAD_TIMEOUT_SECONDS = 1_800
      # replicate.delivery hosts prediction output blobs; replicate.com is the
      # API itself. Refuse to fetch a URL a compromised/odd response pointed
      # us at anywhere else.
      ALLOWED_DOWNLOAD_HOST = /\A([a-z0-9-]+\.)*replicate\.(com|delivery)\z/i.freeze

      def initialize(token: nil)
        @token = token || self.class.load_token
        raise ArgumentError, "missing REPLICATE_API_TOKEN" if @token.to_s.strip.empty?
      end

      def self.load_token
        token = ENV["REPLICATE_API_TOKEN"].to_s.strip
        return token unless token.empty?

        token = ENV["REPLICATE_API_KEY"].to_s.strip
        return token unless token.empty?

        if (contents = read_private_token_file(CONFIG_PATH))
          config = JSON.parse(contents)
          return config.is_a?(Hash) ? config["api_token"].to_s.strip : ""
        end

        token_from_env_file
      rescue StandardError
        ""
      end

      # Validate the path and its opened descriptor before, during and after
      # reading. The path-only permission check is useful for inspection, but
      # must never be the authorization for a later File.read.
      def self.private_token_file?(path)
        full = File.expand_path(path)
        private_token_stats?(File.lstat(full), File.lstat(File.dirname(full)))
      rescue SystemCallError
        false
      end

      def self.read_private_token_file(path)
        full = File.expand_path(path)
        directory_path = File.dirname(full)
        before_directory = File.lstat(directory_path)
        before_file = File.lstat(full)
        return unless private_token_stats?(before_file, before_directory)

        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(full, flags) do |file|
          opened_file = file.stat
          current_file = File.lstat(full)
          current_directory = File.lstat(directory_path)
          return unless private_token_stats?(opened_file, current_directory) &&
                        private_token_stats?(current_file, current_directory)
          return unless same_file?(opened_file, before_file) &&
                        same_file?(opened_file, current_file) &&
                        same_file?(before_directory, current_directory)

          file.binmode
          contents = file.read(MAX_TOKEN_FILE_BYTES + 1)
          return if contents.bytesize > MAX_TOKEN_FILE_BYTES

          final_file = File.lstat(full)
          final_opened_file = file.stat
          final_directory = File.lstat(directory_path)
          return unless private_token_stats?(final_opened_file, final_directory) &&
                        private_token_stats?(final_file, final_directory)
          return unless same_file?(opened_file, final_opened_file) &&
                        same_file?(final_opened_file, final_file) &&
                        same_file?(before_directory, final_directory)

          contents
        end
      rescue SystemCallError, IOError
        nil
      end

      def self.token_from_env_file
        path = File.expand_path("~/.config/master/env")
        contents = read_private_token_file(path)
        return "" unless contents

        contents.each_line do |line|
          key, value = line.strip.sub(/\Aexport\s+/, "").split("=", 2)
          if %w[REPLICATE_API_TOKEN REPLICATE_API_KEY].include?(key) && !value.to_s.empty?
            return value.to_s.delete(%("'))
          end
        end
        ""
      rescue StandardError
        ""
      end

      def self.private_token_stats?(file, directory)
        file.file? && !file.symlink? && file.nlink == 1 &&
          file.size <= MAX_TOKEN_FILE_BYTES && file.uid == Process.uid &&
          (file.mode & 0o077).zero? && directory.directory? && !directory.symlink? &&
          directory.uid == Process.uid && (directory.mode & 0o022).zero?
      end

      def self.same_file?(left, right)
        left.dev == right.dev && left.ino == right.ino
      end
      private_class_method :private_token_stats?, :same_file?

      # owner/name:version pins a version; a bare owner/name takes the latest. A
      # trained LoRA gains a version per training, and frames meant to compare
      # checkpoints have to name the one they came from.
      def predict(model_id, input, timeout: 600)
        timeout = operation_timeout!(timeout, "prediction timeout")
        deadline = monotonic_now + timeout
        pinned = model_id.split(":", 2)[1]
        version = pinned || latest_version(model_id, deadline:)
        pred = post(URI("#{BASE}/predictions"), { version:, input: }, deadline:)
        wait_for(pred["id"], timeout:, deadline:)
      end

      # Bounded catalog read used by Replicate search/sync. Replicate returns a
      # cursor URL; only follow it until the caller's explicit limit is met.
      def models(limit: 100, query: nil)
        remaining = [[limit.to_i, 1].max, 1_000].min
        uri = URI("#{BASE}/models")
        rows = []
        seen_cursors = {}
        pages = 0
        while uri && rows.length < remaining
          pages += 1
          if pages > MAX_MODEL_PAGES
            raise ArgumentError, "Replicate models pagination exceeded #{MAX_MODEL_PAGES} pages"
          end

          cursor = uri.to_s
          raise ArgumentError, "Replicate models pagination repeated a cursor" if seen_cursors[cursor]

          seen_cursors[cursor] = true
          page = get(uri)
          raise TypeError, "Replicate models page must be an object" unless page.is_a?(Hash)

          rows.concat(Array(page["results"]))
          next_url = page["next"].to_s
          uri = next_url.empty? ? nil : models_page_uri(next_url)
        end
        rows = rows.first(remaining)
        needle = query.to_s.strip.downcase
        return rows if needle.empty?

        rows.select do |model|
          [model["owner"], model["name"], model["description"]].compact.join(" ").downcase.include?(needle)
        end
      end

      # SHA-256 of a downloaded file, for provenance sidecars and the
      # content-addressed blob cache in replicate.rb.
      def self.checksum(path)
        require "digest"
        Digest::SHA256.file(path).hexdigest
      end

      def account_username
        account = get(URI("#{BASE}/account"))
        account["username"].to_s.strip
      rescue StandardError
        ENV["REPLICATE_USERNAME"].to_s.strip
      end

      def model_exists?(model_id, deadline: nil)
        owner, name = model_id.split("/")
        get(URI("#{BASE}/models/#{owner}/#{name}"), deadline:)
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ReplicateClient.model_exists?")
        false
      end

      # A LoRA destination serves FLUX.1-dev, and gpu-l40s is the smallest SKU
      # Replicate accepts that holds it; the API refuses names off its list.
      def create_model(model_id, hardware: "gpu-l40s", visibility: "private", deadline: nil)
        owner, name = model_id.split("/", 2)
        raise ArgumentError, "destination must be owner/name" if owner.to_s.empty? || name.to_s.empty?

        post(URI("#{BASE}/models"), {
          owner:,
          name:,
          visibility:,
          hardware:,
        }, deadline:)
      end

      private

      def api_uri(value)
        uri = value.is_a?(URI::Generic) ? value : URI.parse(value.to_s)
        allowed = uri.is_a?(URI::HTTPS) && uri.host == API_HOST && uri.port == 443 &&
                  uri.userinfo.nil? && uri.fragment.nil? && uri.path.start_with?("/v1/")
        raise ArgumentError, "refusing URL outside the Replicate API origin" unless allowed

        uri
      end

      def models_page_uri(value)
        uri = api_uri(value)
        raise ArgumentError, "refusing unexpected Replicate models cursor path" unless uri.path == "/v1/models"

        uri
      end

      def upload_binary(path, mime:)
        source_stat = File.lstat(path)
        unless source_stat.file? && !source_stat.symlink? && File.readable?(path)
          raise ArgumentError, "upload source must be a readable regular non-symlink file"
        end
        raise ArgumentError, "upload exceeds #{MAX_UPLOAD_BYTES} bytes" if source_stat.size > MAX_UPLOAD_BYTES

        boundary = "ReplicateBoundary#{rand(1_000_000_000)}"
        uri = URI("#{BASE}/files")
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Token #{@token}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"

        # Do not allocate a second in-memory copy of a potentially multi-GB ZIP.
        Tempfile.create(["replicate-upload-", ".multipart"], binmode: true) do |body|
          write_multipart_body(body, path, boundary, mime:)
          body.flush
          body.rewind
          req.body_stream = body
          req["Content-Length"] = body.size.to_s
          data = request(req, uri)
          data.dig("urls", "get") || data["serving_url"] || data["url"] || raise("upload missing URL")
        end
      end

      def write_multipart_body(body, path, boundary, mime:)
        filename = File.basename(path).gsub(/[^A-Za-z0-9._-]/, "_")
        filename = "upload.bin" if filename.empty?
        body.write("--#{boundary}\r\n".b)
        body.write("Content-Disposition: form-data; name=\"content\"; filename=\"#{filename}\"\r\n".b)
        body.write("Content-Type: #{mime}\r\n\r\n".b)
        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(path, flags) do |source|
          opened = source.stat
          current = File.lstat(path)
          unless same_file_stat?(opened, current) && opened.file? && !opened.symlink? &&
                 opened.size <= MAX_UPLOAD_BYTES
            raise IOError, "upload source changed before transfer"
          end

          copied = IO.copy_stream(source, body, MAX_UPLOAD_BYTES + 1)
          raise ArgumentError, "upload exceeds #{MAX_UPLOAD_BYTES} bytes" if copied > MAX_UPLOAD_BYTES
          after = source.stat
          final_path = File.lstat(path)
          unless copied == opened.size && same_file_stat?(opened, after) &&
                 same_file_stat?(after, final_path) && stable_file_stat?(opened, after)
            raise IOError, "upload source changed during transfer"
          end
        end
        body.write("\r\n--#{boundary}--\r\n".b)
      end

      # The input parameter names the provider currently declares, from the same
      # GET latest_version already makes.
      #
      # replicate keeps its own MODEL_CAPABILITIES table so it can refuse an
      # unsupported option rather than let the API ignore it — which is the right
      # call, and is also a second source of truth. When Replicate changes a
      # schema the table goes stale, the tests stay green because they only check
      # the table against itself, and the drift shows up as a 422 in production
      # or, worse, as a setting silently dropped.
      def input_keys(model_id)
        owner, name = model_id.split("/")
        model = get(URI("#{BASE}/models/#{owner}/#{name}"))
        schema = model.dig("latest_version", "openapi_schema",
                           "components", "schemas", "Input", "properties")
        Array(schema&.keys)
      end

      def latest_version(model_id, deadline: nil)
        owner, name = model_id.split("/")
        model = get(URI("#{BASE}/models/#{owner}/#{name}"), deadline:)
        model.dig("latest_version", "id") || raise("no version for #{model_id}")
      end

      def get(uri, deadline: nil)
        uri = api_uri(uri)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Token #{@token}"
        request(req, uri, deadline:)
      end

      def post(uri, body, deadline: nil)
        uri = api_uri(uri)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Token #{@token}"
        req["Content-Type"] = "application/json"
        req.body = body.to_json
        request(req, uri, deadline:)
      end

      def request(req, uri, attempts: 3, deadline: nil)
        deadline ||= monotonic_now + REQUEST_TIMEOUT_SECONDS
        last_error = nil
        attempts.times do |attempt|
          req.body_stream.rewind if req.body_stream&.respond_to?(:rewind)
          return attempt_request(req, uri, deadline:)
        rescue ExhaustedError => e
          # Out of the retry loop entirely, and onto the check: no wait inside
          # this run makes the account solvent, and the caller needs to know
          # the capability is gone rather than that one call failed.
          Master::Io::QuotaCheck.trip!(source: "replicate", message: e.message, model: uri.path)
          raise
        rescue TransientError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
               Errno::ECONNRESET, Errno::ETIMEDOUT => e
          # GET is safe to retry. Replicate throttling 429 explicitly rejects
          # the request, but a POST 5xx/read-timeout/reset can hide a paid create
          # that succeeded before its response was lost.
          retryable = req.method == "GET" ||
                      (e.is_a?(TransientError) && e.message.start_with?("Replicate API 429:"))
          raise unless retryable

          last_error = e.message
          break if attempt >= attempts - 1

          pause = [retry_delay(attempt), remaining_timeout(deadline, REQUEST_TIMEOUT_SECONDS, label: "API request")].min
          sleep(pause) if pause.positive?
          remaining_timeout(deadline, REQUEST_TIMEOUT_SECONDS, label: "API request")
        end
        raise last_error
      end

      def attempt_request(req, uri, deadline: monotonic_now + REQUEST_TIMEOUT_SECONDS)
        uri = api_uri(uri)
        response = nil
        body = +"".b
        remaining = remaining_timeout(deadline, OPEN_TIMEOUT_SECONDS, label: "API request")
        Net::HTTP.start(
          uri.host, uri.port, use_ssl: true,
          open_timeout: remaining,
          read_timeout: remaining_timeout(deadline, READ_TIMEOUT_SECONDS, label: "API request"),
          write_timeout: remaining_timeout(deadline, WRITE_TIMEOUT_SECONDS, label: "API request")
        ) do |http|
          http.request(req) do |res|
            response = res
            declared = res["content-length"].to_s
            if declared.match?(/\A\d+\z/) && declared.to_i > MAX_RESPONSE_BYTES
              raise ResponseTooLarge, "Replicate response exceeds #{MAX_RESPONSE_BYTES} bytes"
            end

            res.read_body do |chunk|
              http.read_timeout = remaining_timeout(deadline, READ_TIMEOUT_SECONDS, label: "API response")
              if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES
                raise ResponseTooLarge, "Replicate response exceeds #{MAX_RESPONSE_BYTES} bytes"
              end
              body << chunk
            end
          end
        end
        remaining_timeout(deadline, READ_TIMEOUT_SECONDS, label: "API response finalization")
        raise IOError, "Replicate returned no HTTP response" unless response

        code = response.code.to_i
        return JSON.parse(body) if code.between?(200, 299)

        detail = response_detail(body)
        message = "Replicate API #{code}: response rejected (#{detail})"
        if exhausted?(code, body)
          raise ExhaustedError, "Replicate API #{code}: insufficient credit or quota (#{detail})"
        end
        raise TransientError, message if TRANSIENT_STATUS.include?(code)

        raise message
      end

      # 402 is unambiguous. Beyond it, the body is the only thing that
      # separates "you are going too fast" from "you have no budget", and both
      # arrive as 429.
      def exhausted?(code, body)
        code == 402 || Master::Io::QuotaCheck.exhaustion?(body.to_s)
      end

      def cancel_prediction(id)
        post(URI("#{BASE}/predictions/#{id}/cancel"), {})
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ReplicateClient.cancel_prediction")
        nil
      end

      def cancel_training(id)
        post(URI("#{BASE}/trainings/#{id}/cancel"), {})
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ReplicateClient.cancel_training")
        nil
      end

      def wait_for(id, timeout:, deadline: nil)
        timeout = operation_timeout!(timeout, "prediction timeout")
        deadline ||= monotonic_now + timeout
        loop do
          pred = get(URI("#{BASE}/predictions/#{id}"), deadline:)
          case pred["status"]
          when "succeeded" then return pred["output"]
          when "failed" then raise "prediction failed (#{redacted_provider_error(pred["error"])})"
          when "canceled" then raise "prediction canceled"
          end
          remaining = deadline - monotonic_now
          raise DeadlineExceeded, "prediction deadline exceeded" unless remaining.positive?

          sleep([3, remaining].min)
        end
      rescue DeadlineExceeded
        cancel_prediction(id)
        raise "prediction timeout after #{timeout}s (canceled)"
      end

      def wait_for_training(id, timeout: 3600, deadline: nil)
        timeout = operation_timeout!(timeout, "training timeout")
        deadline ||= monotonic_now + timeout
        loop do
          training = get_training(id, deadline:)
          case training["status"]
          when "succeeded" then return training
          when "failed" then raise "training failed (#{redacted_provider_error(training["error"])})"
          when "canceled" then raise "training canceled"
          end
          remaining = deadline - monotonic_now
          raise DeadlineExceeded, "training deadline exceeded" unless remaining.positive?

          sleep([5, remaining].min)
        end
      rescue DeadlineExceeded
        cancel_training(id)
        raise "training timeout after #{timeout}s (canceled)"
      end

      def retry_delay(attempt)
        base = Master::Ground::FailureTaxonomy.backoff_seconds(attempt).to_f
        # Equal jitter avoids synchronized clients while retaining the shared
        # taxonomy's exponential ceiling and a non-zero minimum delay.
        (base / 2.0) + (rand * base / 2.0)
      end

      def response_detail(body)
        bytes = body.to_s.b
        "response_bytes=#{bytes.bytesize} response_sha256=#{Digest::SHA256.hexdigest(bytes)}"
      end

      def redacted_provider_error(value)
        "provider error redacted (#{response_detail(value)})"
      end

      def same_file_stat?(left, right)
        left.dev == right.dev && left.ino == right.ino
      end

      def stable_file_stat?(before, after)
        before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime
      end

      def operation_timeout!(value, label)
        seconds = Float(value)
        unless seconds.finite? && seconds.positive? && seconds <= 86_400
          raise ArgumentError, "#{label} must be finite and between 0 and 86400 seconds"
        end

        seconds == seconds.to_i ? seconds.to_i : seconds
      rescue ArgumentError, TypeError => error
        raise error if error.is_a?(ArgumentError) && error.message.include?(label)

        raise ArgumentError, "#{label} must be a finite number"
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def remaining_timeout(deadline, cap, label:)
        remaining = deadline - monotonic_now
        raise DeadlineExceeded, "Replicate #{label} deadline exceeded" unless remaining.positive?

        [remaining, cap].min
      end
    end
  end
end
