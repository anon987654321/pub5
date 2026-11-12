# frozen_string_literal: true

require "digest"
require "fileutils"
require "ipaddr"
require "json"
require "net/http"
require "time"
require "timeout"
require "uri"
require_relative "../result"
require_relative "../boot/paths"
require_relative "ssrf_guard"
require_relative "atomic_write"
require_relative "../trace/dmesg"

module Master
  module Io
    # Fixed-origin client for operator-configured Rails applications.
    # Public destinations use the shared pinned-IP SSRF guard. A private
    # destination is possible only when its exact IP is explicitly pinned
    # by the operator at construction time.
    class RailsApiClient
      DEFAULT_TIMEOUT_S = 15
      DEFAULT_RETRIES = 2
      DEFAULT_BACKOFF_S = 0.25
      MAX_TIMEOUT_S = 60
      MAX_RETRIES = 3
      MAX_BODY_BYTES = 2 * 1024 * 1024
      FORBIDDEN_HEADERS = %w[host authorization cookie content-length].freeze

      Response = Data.define(:status, :headers, :body, :elapsed_s) do
        def ok? = status.between?(200, 299)
      end

      class Auth
        def self.build(strategy:, credentials:)
          values = credentials.to_h.transform_keys(&:to_sym)
          case strategy.to_sym
          when :api_key
            header = values.fetch(:header_name, "X-API-Key").to_s
            secret = required_secret(values.fetch(:api_key, nil), "api_key")
            raise ArgumentError, "invalid API-key header name" unless header.match?(/\A[A-Za-z][A-Za-z0-9-]{0,63}\z/)
            new { |request| request[header] = secret }
          when :oauth_token
            secret = required_secret(values[:oauth_token], "oauth_token")
            new { |request| request["Authorization"] = "Bearer #{secret}" }
          when :session_cookie
            secret = required_secret(values[:session_cookie], "session_cookie")
            new { |request| request["Cookie"] = secret }
          else
            raise ArgumentError, "unknown auth strategy: #{strategy}"
          end
        end

        def self.required_secret(value, name)
          secret = value.to_s
          raise ArgumentError, "#{name} is required" if secret.empty?
          raise ArgumentError, "#{name} contains a line break" if secret.match?(/[\r\n]/)
          secret
        end
        private_class_method :required_secret

        def initialize(&apply) = @apply = apply
        def call(request) = @apply.call(request)
      end

      def initialize(base_url:, auth_strategy:, log_root: MasterPaths.state,
                     pinned_address: nil, timeout: DEFAULT_TIMEOUT_S,
                     retries: DEFAULT_RETRIES, backoff: DEFAULT_BACKOFF_S, **credentials)
        @base_uri = parse_base(base_url)
        @auth = Auth.build(strategy: auth_strategy, credentials:)
        @timeout = bounded_number(timeout, 1, MAX_TIMEOUT_S, "timeout")
        @retries = bounded_integer(retries, 0, MAX_RETRIES, "retries")
        @backoff = bounded_number(backoff, 0, 5, "backoff")
        @pinned_address = parse_pinned_address(pinned_address)
        if @pinned_address && !pinned_address_matches_origin?(@pinned_address)
          raise ArgumentError, "pinned_address must match an address resolved for the configured origin"
        end
        if @base_uri.scheme == "http" && @pinned_address.nil?
          raise ArgumentError, "HTTP requires an explicitly pinned operator-approved address"
        end
        @audit_path = File.join(File.expand_path(log_root), "rails_api_client", "audit.ndjson")
        FileUtils.mkdir_p(File.dirname(@audit_path), mode: 0o700)
        File.chmod(0o700, File.dirname(@audit_path))
        @lock = Mutex.new
      end

      def get(path, headers: {}) = request(:get, path, headers:)
      def post(path, body: nil, headers: {}) = request(:post, path, body:, headers:)
      def put(path, body: nil, headers: {}) = request(:put, path, body:, headers:)
      def delete(path, body: nil, headers: {}) = request(:delete, path, body:, headers:)

      def status
        {
          schema: 1, task: "rails_api_client", status: "CONFIGURED",
          origin: "#{@base_uri.scheme}://#{@base_uri.host}:#{@base_uri.port}",
          audit_path: @audit_path, live_request: "NOT_RUN",
        }
      end

      private

      def parse_base(value)
        uri = URI.parse(value.to_s)
        unless uri.is_a?(URI::HTTP) && uri.host && uri.userinfo.nil? &&
               uri.query.nil? && uri.fragment.nil? && uri.path.to_s.match?(%r{\A/?\z})
          raise ArgumentError, "base_url must be an origin without credentials, path, query or fragment"
        end
        raise ArgumentError, "unsupported URL scheme" unless %w[https http].include?(uri.scheme)
        raise ArgumentError, "base_url host is invalid" unless SsrfGuard.valid_resolver_host?(uri.hostname)

        uri
      rescue URI::InvalidURIError
        raise ArgumentError, "base_url is invalid"
      end

      def parse_pinned_address(value)
        return nil if value.nil? || value.to_s.empty?

        IPAddr.new(value.to_s).to_s
      rescue IPAddr::InvalidAddressError
        raise ArgumentError, "pinned_address must be an IP address"
      end

      def bounded_integer(value, minimum, maximum, name)
        number = Integer(value)
        raise ArgumentError, "#{name} must be between #{minimum} and #{maximum}" unless number.between?(minimum, maximum)
        number
      end

      def bounded_number(value, minimum, maximum, name)
        number = Float(value)
        raise ArgumentError, "#{name} must be finite and between #{minimum} and #{maximum}" unless number.finite? && number.between?(minimum, maximum)
        number
      end

      def request(method, path, body: nil, headers: {})
        uri = resolve(path)
        address = destination_address(uri)
        return Result.err("rails_api_client: destination is not permitted", category: :policy) unless address

        attempts = 0
        loop do
          attempts += 1
          begin
            response = perform(method, uri, address:, body:, headers:)
          rescue IOError, SystemCallError, SocketError, Timeout::Error, Net::HTTPError => error
            raise error unless method == :get && attempts <= @retries
            sleep(@backoff * (2**(attempts - 1))) if @backoff.positive?
            next
          end

          audit(method:, uri:, response:, attempts:)
          return Result.ok(response) if response.ok?
          if response.status >= 500 && method == :get && attempts <= @retries
            sleep(@backoff * (2**(attempts - 1))) if @backoff.positive?
            next
          end

          category = response_category(response.status)
          return Result.err("rails_api_client: HTTP #{response.status}", category:, context: { status: response.status })
        end
      rescue ArgumentError, URI::InvalidURIError => error
        Result.err("rails_api_client: #{error.message}", category: :validation)
      rescue StandardError => error
        Result.err("rails_api_client: #{error.class}: #{error.message}", category: :infrastructure)
      end

      def resolve(path)
        raw = path.to_s
        raise ArgumentError, "path must be a non-empty relative path" if raw.empty? || raw.start_with?("//")
        raise ArgumentError, "absolute URLs are not accepted" if raw.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
        raise ArgumentError, "path contains a control character" if raw.match?(/[\x00-\x1f\x7f]/)

        candidate = URI.join(@base_uri.to_s, raw)
        unless candidate.scheme == @base_uri.scheme && candidate.host == @base_uri.host &&
               candidate.port == @base_uri.port && candidate.userinfo.nil?
          raise ArgumentError, "path escapes configured Rails origin"
        end
        candidate
      end

      def pinned_address_matches_origin?(address)
        literal = IPAddr.new(@base_uri.hostname) rescue nil
        return literal.to_s == address if literal

        SsrfGuard.resolve_addresses(@base_uri.hostname).include?(address)
      end

      def destination_address(uri)
        return @pinned_address if @pinned_address

        SsrfGuard.pinned_address(uri)
      end

      def perform(method, uri, address:, body:, headers:)
        klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put,
                  delete: Net::HTTP::Delete }.fetch(method)
        request = klass.new(uri)
        incoming_headers = headers.to_h
        raise ArgumentError, "too many request headers" if incoming_headers.size > 32
        header_bytes = incoming_headers.sum { |name, value| name.to_s.bytesize + value.to_s.bytesize }
        raise ArgumentError, "request headers exceed 16 KB" if header_bytes > 16 * 1024
        incoming_headers.each do |name, value|
          key = name.to_s
          raise ArgumentError, "header #{key} is managed by the client" if FORBIDDEN_HEADERS.include?(key.downcase)
          raise ArgumentError, "header value contains a line break" if value.to_s.match?(/[\r\n]/)
          request[key] = value.to_s
        end
        unless body.nil?
          request["Content-Type"] ||= "application/json"
          request.body = body.is_a?(String) ? body : JSON.generate(body)
          raise ArgumentError, "request body exceeds #{MAX_BODY_BYTES} bytes" if request.body.bytesize > MAX_BODY_BYTES
        end
        @auth.call(request)

        http = SsrfGuard.http_for(uri, address, timeout: @timeout)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        captured = nil
        http.start do |connection|
          connection.request(request) do |response|
            content = +"".b
            response.read_body do |chunk|
              raise IOError, "response body exceeds #{MAX_BODY_BYTES} bytes" if content.bytesize + chunk.bytesize > MAX_BODY_BYTES
              content << chunk
            end
            captured = Response.new(
              status: response.code.to_i, headers: response.to_hash,
              body: content.force_encoding(Encoding::UTF_8).scrub,
              elapsed_s: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
            )
          end
        end
        captured || raise(IOError, "HTTP response was not captured")
      end

      def response_category(status)
        return :auth_error if [401, 403].include?(status)
        return :rate_limit if status == 429
        return :validation if status == 400 || status == 404 || status == 422
        return :invalid_request if status.between?(300, 499)

        :infrastructure
      end

      def audit(method:, uri:, response:, attempts:)
        row = {
          at: Time.now.utc.iso8601, method: method.to_s.upcase, host: uri.host,
          path_digest: Digest::SHA256.hexdigest(uri.path), status: response.status, attempts:,
          elapsed_ms: (response.elapsed_s * 1000).round,
        }
        @lock.synchronize do
          raise IOError, "API audit path must not be a symlink" if File.symlink?(@audit_path)
          File.open(@audit_path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
            file.chmod(0o600)
            file.flock(File::LOCK_EX)
            file.puts(JSON.generate(row))
            file.flush
          ensure
            file&.flock(File::LOCK_UN) rescue nil
          end
        end
      rescue StandardError => error
        Master::Trace::Dmesg.status("api0", "audit write failed, #{error.class}")
      end
    end
  end
end
