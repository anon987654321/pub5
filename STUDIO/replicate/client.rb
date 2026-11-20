# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "yaml"
require "securerandom"
require "tempfile"
require "timeout"
require "uri"
require "ipaddr"
require "socket"
require_relative "../lora/consent"
require_relative "models"

module Studio
  # Studio-owned provider client. MASTER has its own client and runtime policies.
  class ReplicateClient
      # File upload/download helpers — separate from ReplicateClient's own
      # prediction/training/model-catalog API.
      module AssetTransfer
        def upload_file(path, subject:)
          authorize_subject!(subject, action: :generation)
          mime = case File.extname(path).downcase
                 when ".jpg", ".jpeg" then "image/jpeg"
                 when ".png" then "image/png"
                 when ".webp" then "image/webp"
                 when ".gif" then "image/gif"
                 else
                   raise ArgumentError, "unsupported image type #{File.extname(path)}"
                 end

          validate_upload_source!(path)
          upload_binary(path, mime:)
        end

        def upload_zip(path, subject:)
          authorize_subject!(subject, action: :training)
          validate_private_training_zip!(path)
          upload_binary(path, mime: "application/zip")
        end

        private

        def authorize_subject!(subject, action:)
          name = subject.to_s
          raise ArgumentError, "subject must be a simple directory name" unless
            name.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/)

          subject_directory = File.join(File.expand_path("../lora", __dir__), name)
          Studio::Lora::Consent.require!(subject: name, subject_directory:, action:)
        end

        def validate_private_training_zip!(path)
          validate_upload_source!(path)
          stat = File.lstat(path)
          unless stat.file? && !stat.symlink? && stat.uid == Process.uid &&
                 stat.nlink == 1 && (stat.mode & 0o077).zero?
            raise ArgumentError, "training ZIP must be a singly-linked owner-only (0600) regular file"
          end
          path
        end
        private :validate_private_training_zip!

        def validate_upload_source!(path)
          raise ArgumentError, "upload source must be a readable regular, non-symlink file" unless
            File.file?(path) && !File.symlink?(path) && File.readable?(path)

          raise ArgumentError, "upload exceeds #{MAX_UPLOAD_BYTES} bytes" if File.size(path) > MAX_UPLOAD_BYTES

          path
        end

        public

        # Fetch a prediction output URL (e.g. synthesized audio) to a local path.
        # Streamed under a byte cap, so a response that misstates its size cannot
        # fill the disk; the default is the largest thing a run fetches, a trainer
        # tar. A failed fetch leaves no partial file.
        def download_url(url, path, max_bytes: MAX_DOWNLOAD_BYTES, timeout: 600)
          uri = URI(url.to_s)
          raise ArgumentError, "refusing non-https download url" unless uri.is_a?(URI::HTTPS) && uri.port == 443
          raise ArgumentError, "refusing download URL credentials" unless uri.userinfo.nil?
          raise ArgumentError, "refusing download URL fragment" unless uri.fragment.nil?
          raise ArgumentError, "refusing download from untrusted host: #{uri.host}" unless uri.host.to_s.match?(ALLOWED_DOWNLOAD_HOST)

          max_bytes = Integer(max_bytes)
          raise ArgumentError, "download byte limit must be positive" unless max_bytes.positive?
          timeout = operation_timeout!(timeout, "download timeout")
          deadline = monotonic_now + timeout

          target = File.expand_path(path.to_s)
          basename = File.basename(target)
          raise ArgumentError, "download target must name a file" if basename.empty? || basename == File::SEPARATOR

          directory = File.dirname(target)
          FileUtils.mkdir_p(directory)
          directory = File.realpath(directory)
          target = File.join(directory, basename)
          raise ArgumentError, "refusing to replace a symlink download target" if File.symlink?(target)
          raise ArgumentError, "download target exists and is not a regular file" if File.exist?(target) && !File.file?(target)
          mode = File.file?(target) ? File.stat(target).mode & 0o7777 : 0o640
          # Validate filesystem state before DNS activity; an invalid target must
          # not cause even a provider hostname lookup.
          pin = ReplicateClient.public_download_address!(uri.host)

          # Keep the old output intact until the entire response has passed its
          # status, byte-limit and monotonic-deadline checks. The temporary lives
          # beside the canonical target so the final rename stays atomic.
          Tempfile.create(["replicate-download-", ".part"], directory, binmode: true) do |file|
            # A proxy inherited from the environment would route around ipaddr=
            # and send the request to a different socket destination.
            http = Net::HTTP.new(uri.host, uri.port, nil)
            raise SocketError, "Net::HTTP cannot pin Replicate destination" unless http.respond_to?(:ipaddr=)
            http.ipaddr = pin
            http.use_ssl = true
            http.open_timeout = [OPEN_TIMEOUT_SECONDS, timeout].min
            http.read_timeout = [READ_TIMEOUT_SECONDS, timeout].min
            http.write_timeout = [WRITE_TIMEOUT_SECONDS, timeout].min
            http.start do |conn|
              conn.request_get(uri.request_uri) do |res|
                raise "download failed #{res.code}" unless res.code.to_i.between?(200, 299)
                raise "download over #{max_bytes} bytes" if res["content-length"].to_s.to_i > max_bytes

                write_capped(res, file, max_bytes, deadline:)
              end
            end
            raise IOError, "Replicate download exceeded its #{timeout}s deadline" if monotonic_now >= deadline
            raise ArgumentError, "refusing to replace a symlink download target" if File.symlink?(target)
            raise ArgumentError, "download target became a non-regular file" if File.exist?(target) && !File.file?(target)

            file.flush
            file.fsync
            File.chmod(mode, file.path)

            file.close
            File.rename(file.path, target)
          end
          path
        end

        private

        def write_capped(res, file, max_bytes, deadline:)
          written = 0
          res.read_body do |chunk|
            raise IOError, "Replicate download exceeded its monotonic deadline" if monotonic_now >= deadline

            written += chunk.bytesize
            raise "download over #{max_bytes} bytes" if written > max_bytes

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
        # Start the pinned Replicate fast-FLUX subject trainer. The ZIP is
        # uploaded separately; only its URL, trigger, subject type, step count
        # and reproducible seed are sent to this trainer version.
        def train_lora(
          photos_zip_url,
          destination,
          trigger_word: nil,
          training_steps: nil,
          lora_type: nil,
          seed: nil,
          timeout: 3600,
          webhook: nil,
          webhook_events_filter: nil,
          wait: true,
          version: nil,
          subject:
        )
          subject_name = subject.to_s
          raise ArgumentError, "subject must be a simple directory name" unless
            subject_name.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/)
          subject_directory = File.join(File.expand_path("../lora", __dir__), subject_name)
          Studio::Lora::Consent.require!(subject: subject_name, subject_directory:, action: :training)

          timeout = operation_timeout!(timeout, "training timeout")
          photos_zip_url = training_zip_url!(photos_zip_url)
          standards = TRAINING_STANDARDS.fetch("replicate")
          trigger_word = training_trigger_for_subject(subject_directory, trigger_word)
          training_steps = standards.fetch("training_steps") if training_steps.nil?
          lora_type = standards.fetch("lora_type") if lora_type.nil?
          seed = standards.fetch("seed") if seed.nil?
          raise ArgumentError, "training_steps must match the shared standard (#{standards.fetch("training_steps")})" unless training_steps == standards.fetch("training_steps")
          raise ArgumentError, "lora_type must be #{standards.fetch("lora_type").inspect}" unless lora_type == standards.fetch("lora_type")
          raise ArgumentError, "seed must match the shared standard (#{standards.fetch("seed")})" unless seed == standards.fetch("seed")
          positive_integer!(training_steps, "training_steps")
          positive_integer!(seed, "seed")
          raise ArgumentError, "wait must be true or false" unless wait == true || wait == false
          resource_id!(version || trainer_version, "trainer version")

          owner, model_name, pinned = model_reference!(destination)
          raise ArgumentError, "training destination must be owner/model without a version" if pinned
          destination = "#{owner}/#{model_name}"

          trainings_uri, body = build_training_request(
            photos_zip_url, destination, trigger_word:, training_steps:, lora_type:, seed:,
            webhook:, webhook_events_filter:, version:
          )
          trainer_owner, trainer_name, = model_reference!(LORA_TRAINER)
          trainer_version_id = resource_id!(version || trainer_version, "trainer version")
          validate_input_schema!("#{trainer_owner}/#{trainer_name}:#{trainer_version_id}", body.fetch(:input))
          ensure_private_model!(destination)

          training = post(trainings_uri, body)
          wait ? wait_for_training(training["id"], timeout:) : training
        end

        def training_trigger_for_subject(directory, supplied)
          path = File.join(directory, "train.yaml")
          raise ArgumentError, "subject train.yaml is missing or is a symlink" unless File.file?(path) && !File.symlink?(path)
          raise ArgumentError, "subject training plan exceeds 1 MB" if File.size(path) > 1_048_576

          plan = YAML.safe_load(File.read(path, encoding: "UTF-8"),
                                permitted_classes: [], permitted_symbols: [], aliases: false)
          expected_subject = File.basename(directory)
          raise ArgumentError, "subject training plan must identify #{expected_subject}" unless
            plan.is_a?(Hash) && plan["schema"] == 1 && plan["subject"] == expected_subject
          expected = training_trigger!(plan["trigger_word"])
          raise ArgumentError, "trigger_word does not match #{expected_subject}/train.yaml" if supplied && training_trigger!(supplied) != expected

          expected
        rescue Psych::Exception => error
          raise ArgumentError, "invalid subject training plan #{path}: #{error.message}"
        end
        private :training_trigger_for_subject

        def get_training(id)
          get(URI("#{BASE}/trainings/#{resource_id!(id, "training id")}"))
        end

        # The trainer version a run will use, so a sidecar can name it. A moving
        # "latest" makes two trainings of one dataset incomparable.
        def trainer_version
          LORA_TRAINER_VERSION
        end

        # Pick a training up by id after an --async start or an interrupted poll.
        def resume_training(id, timeout: 3600)
          timeout = operation_timeout!(timeout, "training timeout")
          training = get_training(id)
          training["status"] == "succeeded" ? training : wait_for_training(id, timeout:)
        end

        def stop_training(id)
          cancel_training(id)
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

        def training_zip_url!(value)
          uri = URI.parse(value.to_s)
          valid = uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty? && uri.userinfo.nil? && uri.fragment.nil?
          raise ArgumentError, "training ZIP URL must be an HTTPS URL without credentials or a fragment" unless valid

          uri.to_s
        rescue URI::InvalidURIError
          raise ArgumentError, "training ZIP URL must be a valid HTTPS URL"
        end

        def training_trigger!(value)
          trigger = value.to_s
          raise ArgumentError, "trigger_word must be a simple 1-64 character token" unless trigger.match?(/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/)

          trigger
        end

        def positive_integer!(value, label)
          raise ArgumentError, "#{label} must be a positive Integer" unless value.is_a?(Integer) && value.positive?

          value
        end

        def build_training_request(photos_zip_url, destination, trigger_word:, training_steps:, lora_type:, seed:, webhook:, webhook_events_filter:, version: nil)
          trainer_owner, trainer_name, = model_reference!(LORA_TRAINER)
          trainer_version_id = resource_id!(version || trainer_version, "trainer version")
          trainings_uri = URI("#{BASE}/models/#{trainer_owner}/#{trainer_name}/versions/#{trainer_version_id}/trainings")
          input = {
            input_images: photos_zip_url,
            trigger_word:,
            lora_type:,
            training_steps:,
            seed:,
          }
          body = { destination:, input: }
          body[:webhook] = webhook if webhook.to_s.strip != ""
          body[:webhook_events_filter] = Array(webhook_events_filter) if webhook_events_filter
          [trainings_uri, body]
        end
      end

      # One prediction with its metrics, and the schema check that guards it.
      # Grouped apart from ReplicateClient for the same reason as Training: the
      # class stays under the public-method ceiling.
      module Prediction
        # The whole prediction object: id and metrics ride with the output, so a
        # caller can log what a frame cost. Prefer: wait holds the request for a
        # sync answer, which suits models that take seconds; Cancel-After is the
        # server-side deadline, so a stuck run stops billing even if this process
        # dies.
        def run(model_id, input, timeout: 600)
          timeout = operation_timeout!(timeout, "prediction timeout")
          owner, name, pinned = model_reference!(model_id)
          version = pinned || latest_version("#{owner}/#{name}")
          validate_input_schema!("#{owner}/#{name}:#{version}", input)
          Models.reserve_video_spend!("#{owner}/#{name}", input)
          headers = {
            "Prefer" => "wait=#{[timeout, MAX_SYNC_WAIT].min}",
            "Cancel-After" => "#{timeout.clamp(CANCEL_AFTER_RANGE)}s",
          }
          pred = post(URI("#{BASE}/predictions"), { version:, input: }, headers:)
          settle(pred, timeout:)
        end

        # The input names a model declares, for refusing a key it would ignore.
        def input_names(model_id)
          input_keys(model_id)
        end

        private

        def validate_input_schema!(model_id, input)
          raise ArgumentError, "prediction input must be a Hash" unless input.is_a?(Hash)

          schema = input_schema(model_id)
          properties = schema.fetch("properties")
          allowed = properties.keys.map(&:to_s)
          supplied = input.keys.map(&:to_s)
          raise ArgumentError, "prediction input contains duplicate string/symbol keys" unless supplied.uniq.length == supplied.length

          unknown = supplied - allowed
          raise ArgumentError, "unsupported inputs for #{model_id}: #{unknown.join(", ")}" unless unknown.empty?

          required = Array(schema["required"]).map(&:to_s)
          missing = required - supplied
          raise ArgumentError, "missing required inputs for #{model_id}: #{missing.join(", ")}" unless missing.empty?

          true
        end
      end

      include AssetTransfer
      include Training
      include Prediction

      # Raised for HTTP statuses worth a retry (rate limit, server-side fault).
      # A 4xx other than 429 means the request itself is wrong and retrying
      # retries repeat the same failure.
      TransientError = Class.new(StandardError)

      # A non-retryable 4xx response retains its status so callers can
      # distinguish a genuinely missing model from denied access or bad input.
      SchemaUnavailable = Class.new(StandardError)

      APIError = Class.new(StandardError) do
        attr_reader :status, :response_body

        def initialize(status, response_body)
          @status = Integer(status)
          @response_body = response_body.to_s.freeze
          super("Replicate API #{@status}: #{@response_body}")
        end
      end

      # A spend limit. The status codes alone could not tell this apart: a
      # 402 already fell through to the plain raise and was handled correctly
      # by accident, but Replicate also answers 429 when the account is out of
      # budget rather than merely too fast — and TRANSIENT_STATUS reads every
      # 429 as a throttle, so those were retried three times with backoff to
      # buy the same refusal three times. Named so the retry loop can tell a
      # wait that will help from one that cannot.
      ExhaustedError = Class.new(StandardError)
      DeadlineExceeded = Class.new(Timeout::Error)

      CONFIG_PATH = File.expand_path("~/.config/replicate/config.json").freeze
      BASE = "https://api.replicate.com/v1"
      TRAINING_STANDARDS_PATH = File.expand_path("../lora/training_standards.yml", __dir__).freeze
      TRAINING_STANDARDS = YAML.safe_load_file(
        TRAINING_STANDARDS_PATH, permitted_classes: [], permitted_symbols: [], aliases: false
      ).freeze
      LORA_TRAINER = TRAINING_STANDARDS.fetch("replicate").fetch("trainer").freeze
      # The trainer pin and request defaults live in training_standards.yml.
      # Changing them requires a reviewed input-schema update and regression tests.
      LORA_TRAINER_VERSION = TRAINING_STANDARDS.fetch("replicate").fetch("version").freeze
      TRANSIENT_STATUS = ((500..599).to_a << 429).freeze
      MAX_DOWNLOAD_BYTES = 4 * 1024**3
      MAX_UPLOAD_BYTES = 4 * 1024**3
      MAX_RESPONSE_BYTES = 16 * 1024**2
      API_HOST = "api.replicate.com"
      OPEN_TIMEOUT_SECONDS = 10
      READ_TIMEOUT_SECONDS = 120
      WRITE_TIMEOUT_SECONDS = 120
      API_TOTAL_TIMEOUT_SECONDS = 180
      MAX_API_TOTAL_TIMEOUT_SECONDS = 600
      MAX_MODEL_PAGES = 1_000

      # Replicate holds a sync request 60 seconds at most; Cancel-After takes
      # 5 seconds to 24 hours.
      MAX_SYNC_WAIT = 60
      CANCEL_AFTER_RANGE = (5..86_400).freeze
      # replicate.delivery hosts prediction output blobs; replicate.com is the
      # API itself. Refuse to fetch a URL a compromised/odd response pointed
      # us at anywhere else.
      ALLOWED_DOWNLOAD_HOST = /\A([a-z0-9-]+\.)*replicate\.(com|delivery)\z/i.freeze
      # Even an allowlisted name must resolve only to public addresses. A
      # rebinding answer that later points at loopback or link-local would
      # otherwise let download_url talk to the host itself.
      BLOCKED_DOWNLOAD_RANGES = %w[
        0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
        172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
        192.31.196.0/24 192.52.193.0/24 192.88.99.0/24 192.168.0.0/16 192.175.48.0/24
        198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
        ::/96 ::1/128 64:ff9b::/96 64:ff9b:1::/48 100::/64 2001::/23
        2001:db8::/32 2002::/16 2620:4f:8000::/48 2d00::/8 2e00::/7 3000::/5 3800::/6
        3c00::/7 3e00::/8 3f00::/8 fec0::/10 fc00::/7 fe80::/10 ff00::/8
      ].map { |cidr| IPAddr.new(cidr) }.freeze
      GLOBAL_DOWNLOAD_IPV6 = IPAddr.new("2000::/3").freeze
      DNS_RESOLUTION_TIMEOUT_S = 5
      MODEL_REFERENCE = /\A([A-Za-z0-9][A-Za-z0-9._-]{0,127})\/([A-Za-z0-9][A-Za-z0-9._-]{0,127})(?::([A-Za-z0-9][A-Za-z0-9._-]{0,127}))?\z/.freeze
      RESOURCE_ID = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/.freeze

      def initialize(token: nil)
        @token = token || self.class.load_token
        raise ArgumentError, "missing REPLICATE_API_TOKEN" if @token.to_s.strip.empty?
      end

      def self.load_token
        token = ENV["REPLICATE_API_TOKEN"].to_s.strip
        return token unless token.empty?

        token = ENV["REPLICATE_API_KEY"].to_s.strip
        return token unless token.empty?

        if private_token_file?(CONFIG_PATH)
          return JSON.parse(File.read(CONFIG_PATH))["api_token"].to_s.strip
        end

        token_from_env_file
      rescue StandardError
        ""
      end


      def self.resolve_download_addresses(host)
        Timeout.timeout(DNS_RESOLUTION_TIMEOUT_S) do
          Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
        end
      rescue SocketError, SystemCallError, Timeout::Error
        []
      end

      def self.valid_download_hostname?(host)
        candidate = host.to_s.downcase.delete_suffix(".")
        return false if candidate.empty? || candidate.bytesize > 253

        labels = candidate.split(".", -1)
        return false if labels.length < 2

        labels.all? do |label|
          label.bytesize <= 63 && label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/)
        end
      end

      def self.public_download_address!(host)
        host = host.to_s.downcase.delete_suffix(".")
        raise ArgumentError, "refusing invalid download host" unless valid_download_hostname?(host)

        addresses = resolve_download_addresses(host)
        raise ArgumentError, "download host did not resolve: #{host}" if addresses.empty?
        normalized = addresses.map do |addr|
          ip = IPAddr.new(addr)
          if blocked_download_ip?(ip)
            raise ArgumentError, "refusing download host resolving to non-public address: #{host} -> #{addr}"
          end
          ip = ip.native if ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped?
          ip.to_s
        end
        normalized.first
      rescue IPAddr::InvalidAddressError => e
        raise ArgumentError, "download host returned an invalid address: #{host}: #{e.message}"
      end

      def self.blocked_download_ip?(ip)
        ip = ip.native if ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped?
        ip.loopback? || ip.link_local? || ip.private? ||
          (ip.ipv6? && !GLOBAL_DOWNLOAD_IPV6.include?(ip)) ||
          (ip.respond_to?(:multicast?) && ip.multicast?) ||
          BLOCKED_DOWNLOAD_RANGES.any? { |range| range.include?(ip) }
      rescue StandardError
        true
      end

      def self.private_token_file?(path)
        file = File.lstat(path)
        directory = File.lstat(File.dirname(path))
        file.file? && !file.symlink? && file.nlink == 1 && file.uid == Process.uid &&
          (file.mode & 0o077).zero? && directory.directory? && !directory.symlink? &&
          directory.uid == Process.uid && (directory.mode & 0o022).zero?
      rescue SystemCallError
        false
      end

      def self.token_from_env_file
        path = File.expand_path("~/.config/master/env")
        return "" unless private_token_file?(path)

        File.foreach(path) do |line|
          key, value = line.strip.sub(/\Aexport\s+/, "").split("=", 2)
          if %w[REPLICATE_API_TOKEN REPLICATE_API_KEY].include?(key) && !value.to_s.empty?
            return value.to_s.delete(%("'))
          end
        end
        ""
      rescue StandardError
        ""
      end

      # owner/name:version pins a version; a bare owner/name takes the latest. A
      # trained LoRA gains a version per training, and frames meant to compare
      # checkpoints have to name the one they came from.
      def predict(model_id, input, timeout: 600)
        run(model_id, input, timeout:)["output"]
      end

      # Bounded catalog read used by Replicate search/sync. Replicate returns a
      # cursor URL; only follow it until the caller's explicit limit is met.
      def models(limit: 100, query: nil)
        requested = if limit.is_a?(Integer)
                      limit
                    elsif limit.is_a?(String) && limit.match?(/\A\d+\z/)
                      Integer(limit, 10)
                    end
        raise ArgumentError, "model limit must be a positive integer" unless requested&.positive?

        remaining = [requested, 1_000].min
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

      def model_exists?(model_id)
        owner, name, = model_reference!(model_id)
        get(URI("#{BASE}/models/#{owner}/#{name}"))
        true
      rescue APIError => error
        return false if error.status == 404

        raise
      end

      # Replicate's model endpoint exposes visibility. Training into an
      # existing public model would publish the resulting weights, so refuse it.
      def model_visibility(model_id)
        owner, name, pinned = model_reference!(model_id)
        raise ArgumentError, "visibility lookup needs owner/name without a version" if pinned

        value = get(URI("#{BASE}/models/#{owner}/#{name}"))["visibility"].to_s
        raise "Replicate did not report model visibility for #{owner}/#{name}" unless %w[private public].include?(value)

        value
      end

      def ensure_private_model!(model_id)
        if model_exists?(model_id)
          visibility = model_visibility(model_id)
          raise ArgumentError, "training destination #{model_id} is #{visibility}; refusing to publish private identity weights" unless visibility == "private"
        else
          create_model(model_id, visibility: "private")
        end
        model_id
      end

      # A LoRA destination serves FLUX.1-dev, and gpu-l40s is the smallest SKU
      # Replicate accepts that holds it; the API refuses names off its list.
      def create_model(model_id, hardware: "gpu-l40s", visibility: "private")
        owner, name, pinned = model_reference!(model_id)
        raise ArgumentError, "destination must be owner/name without a version" if pinned

        post(URI("#{BASE}/models"), {
          owner:,
          name:,
          visibility:,
          hardware:,
        })
      end

      private

      def model_reference!(value)
        match = MODEL_REFERENCE.match(value.to_s)
        raise ArgumentError, "model reference must be owner/name with an optional pinned version" unless match

        match.captures
      end

      def resource_id!(value, label)
        identifier = value.to_s
        raise ArgumentError, "invalid Replicate #{label}" unless RESOURCE_ID.match?(identifier)

        identifier
      end

      def upload_binary(path, mime:)
        validate_upload_source!(path)

        boundary = "ReplicateBoundary#{SecureRandom.hex(18)}"
        uri = URI("#{BASE}/files")
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Token #{@token}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"

        # Stream the multipart payload from a temporary file instead of holding
        # an entire dataset ZIP in a second, equally large Ruby String.
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
        File.open(path, "rb") do |source|
          copied = IO.copy_stream(source, body, MAX_UPLOAD_BYTES + 1)
          raise ArgumentError, "upload exceeds #{MAX_UPLOAD_BYTES} bytes" if copied > MAX_UPLOAD_BYTES
        end
        body.write("\r\n--#{boundary}--\r\n".b)
      end

      # Read the provider's OpenAPI schema for the exact pinned version.
      # A local capability table would become a second, drifting source of truth.
      def input_schema(model_id)
        owner, name, pinned = model_reference!(model_id)
        cache_key = [owner, name, pinned || "latest"].join("/")
        @input_schema_cache ||= {}
        return @input_schema_cache.fetch(cache_key) if @input_schema_cache.key?(cache_key)

        schema = if pinned
                   version = get(URI("#{BASE}/models/#{owner}/#{name}/versions/#{pinned}"))
                   version.dig("openapi_schema", "components", "schemas", "Input")
                 else
                   model = get(URI("#{BASE}/models/#{owner}/#{name}"))
                   model.dig("latest_version", "openapi_schema", "components", "schemas", "Input")
                 end
        unless schema.is_a?(Hash) && schema["properties"].is_a?(Hash) && !schema["properties"].empty?
          raise SchemaUnavailable, "Replicate did not provide an input schema for #{owner}/#{name}#{pinned ? ":#{pinned}" : ""}"
        end

        @input_schema_cache[cache_key] = schema
      end

      def input_keys(model_id)
        input_schema(model_id).fetch("properties").keys
      end

      def latest_version(model_id)
        owner, name, = model_reference!(model_id)
        model = get(URI("#{BASE}/models/#{owner}/#{name}"))
        model.dig("latest_version", "id") || raise("no version for #{model_id}")
      end

      def get(uri)
        uri = api_uri(uri)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Token #{@token}"
        request(req, uri)
      end

      def post(uri, body, headers: {})
        uri = api_uri(uri)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Token #{@token}"
        req["Content-Type"] = "application/json"
        headers.each { |name, value| req[name] = value }
        req.body = body.to_json
        request(req, uri)
      end

      def request(req, uri, attempts: 3)
        last_error = nil
        attempts.times do |attempt|
          req.body_stream.rewind if req.body_stream&.respond_to?(:rewind)

          return attempt_request(req, uri)
        rescue ExhaustedError => e
          # Out of the retry loop entirely, and onto the check: no wait inside
          # this run makes the account solvent, and the caller needs to know
          # the capability is gone rather than that one call failed.
          warn("replicate quota exhausted: #{e.message}")

          raise
        rescue TransientError, DeadlineExceeded, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT => e
          # GET is safe to retry. Replicate throttling 429 explicitly rejects
          # the request, but a POST 5xx/read-timeout/reset can hide a paid create
          # that succeeded before its response was lost.
          retryable = req.method == "GET" ||
                      (e.is_a?(TransientError) && e.message.start_with?("Replicate API 429:"))
          raise unless retryable

          last_error = e
          sleep(retry_delay(e.message, attempt)) if attempt < attempts - 1
        end
        raise last_error
      end

      def attempt_request(req, uri, timeout: API_TOTAL_TIMEOUT_SECONDS)
        uri = api_uri(uri)
        total = Float(timeout)
        unless total.finite? && total.positive? && total <= MAX_API_TOTAL_TIMEOUT_SECONDS
          raise ArgumentError, "Replicate API total timeout must be finite and between 0 and #{MAX_API_TOTAL_TIMEOUT_SECONDS}s"
        end
        response = nil
        body = +"".b
        pin = ReplicateClient.public_download_address!(uri.host)
        http = Net::HTTP.new(uri.host, uri.port, nil)
        raise SocketError, "Net::HTTP cannot pin Replicate API destination" unless http.respond_to?(:ipaddr=)

        http.ipaddr = pin
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT_SECONDS
        http.read_timeout = READ_TIMEOUT_SECONDS
        http.write_timeout = WRITE_TIMEOUT_SECONDS
        Timeout.timeout(total, DeadlineExceeded, "Replicate API request exceeded #{total}s total deadline") do
          http.start do |conn|
            conn.request(req) do |res|
              response = res
              declared = res["content-length"].to_s
              if !declared.empty? && declared.match?(/\A\d+\z/) && declared.to_i > MAX_RESPONSE_BYTES
                raise ArgumentError, "Replicate response exceeds #{MAX_RESPONSE_BYTES} bytes"
              end
              res.read_body do |chunk|
                raise ArgumentError, "Replicate response exceeds #{MAX_RESPONSE_BYTES} bytes" if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES

                body << chunk
              end
            end
          end
        end
        raise IOError, "Replicate returned no HTTP response" unless response

        code = response.code.to_i
        return JSON.parse(body) if code.between?(200, 299)

        message = "Replicate API #{code}: #{body}"
        raise ExhaustedError, message if exhausted?(code, body)
        raise TransientError, message if TRANSIENT_STATUS.include?(code)

        raise APIError.new(code, body)
      end

      # Replicate says when a throttle clears ("resets in ~30s"); waiting that
      # long beats a blind exponential guess in both directions.
      def api_uri(value)
        uri = value.is_a?(URI::Generic) ? value : URI.parse(value.to_s)
        allowed = uri.is_a?(URI::HTTPS) && uri.host == API_HOST && uri.port == 443 &&
                  uri.userinfo.nil? && uri.fragment.nil?
        allowed &&= uri.path.start_with?("/v1/") &&
                    uri.path.split("/").none? { |segment| segment == "." || segment == ".." || segment.include?("%") }
        raise ArgumentError, "refusing URL outside the Replicate API origin" unless allowed

        uri
      end

      def models_page_uri(value)
        uri = api_uri(value)
        raise ArgumentError, "refusing unexpected Replicate models cursor path" unless uri.path == "/v1/models"

        uri
      end

      def retry_delay(message, attempt)
        reset = message.to_s[/resets in ~?(\d+)s/, 1]
        [reset ? reset.to_i + 1 : 2**attempt, 60].min
      end

      # 402 is unambiguous. Beyond it, the body is the only thing that
      # separates "you are going too fast" from "you have no budget", and both
      # arrive as 429.
      def exhausted?(code, body)
        code == 402 || body.to_s.match?(/(?:insufficient|exhausted|no\s+credit|quota|billing|budget)/i)
      end

      def cancel_prediction(id)
        prediction_id = resource_id!(id, "prediction id")
        post(URI("#{BASE}/predictions/#{prediction_id}/cancel"), {})
      rescue StandardError => e
        warn("replicate cancel prediction failed: #{e.class}: #{e.message}")
        nil
      end

      def cancel_training(id)
        training_id = resource_id!(id, "training id")
        post(URI("#{BASE}/trainings/#{training_id}/cancel"), {})
      rescue StandardError => e
        warn("replicate cancel training failed: #{e.class}: #{e.message}")
        nil
      end

      # A create answered under Prefer: wait may already be finished; otherwise
      # poll the same prediction, easing off from 1s to 5s.
      def settle(pred, timeout:)
        timeout = operation_timeout!(timeout, "prediction timeout")
        prediction_id = resource_id!(pred["id"], "prediction id")
        deadline = monotonic_now + timeout
        delay = 1

        loop do
          case pred["status"]
          when "succeeded" then return pred
          when "failed" then raise "prediction failed: #{pred['error']}"
          when "canceled" then raise "prediction canceled"
          end

          remaining = deadline - monotonic_now
          if remaining <= 0
            cancel_prediction(pred["id"])
            raise "prediction timeout after #{timeout}s (canceled)"
          end
          sleep [delay, remaining].min
          delay = [delay + 1, 5].min
          pred = get(URI("#{BASE}/predictions/#{prediction_id}"))
        end
      end

      def wait_for_training(id, timeout: 3600)
        timeout = operation_timeout!(timeout, "training timeout")
        training_id = resource_id!(id, "training id")
        deadline = monotonic_now + timeout
        delay = 5
        loop do
          training = get_training(training_id)

          case training["status"]
          when "succeeded" then return training
          when "failed" then raise "training failed: #{training['error']}"
          when "canceled" then raise "training canceled"
          end

          remaining = deadline - monotonic_now
          if remaining <= 0
            cancel_training(id)
            raise "training timeout after #{timeout}s (canceled)"
          end
          sleep [delay, remaining].min
          delay = [delay + 2, 15].min
        end
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
    end
  end
