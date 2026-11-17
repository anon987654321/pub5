# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "time"

module Master
  module Ground
    # Publishes only the completed operation report supplied by the local CLI.
    # The caller never hands this class a conversation transcript or a log
    # directory. Anonymous pastes are link-accessible, so reports are redacted,
    # bounded and short-lived before any request leaves the machine.
    class PastePublisher
      MAX_BYTES = 96 * 1024
      OPERATION_MAX_CHARS = 240
      OPEN_TIMEOUT = 2
      READ_TIMEOUT = 3
      WRITE_TIMEOUT = 3
      EXPIRY = "1d"
      ANSI = /\e(?:\[[0-?]*[ -\/]*[@-~]|\][^\a]*(?:\a|\e\\))/
      PRIVATE_KEY_BLOCK = /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----/mi
      SENSITIVE_ASSIGNMENT = /\b([A-Z0-9_.-]*(?:PASSWORD|PASSWD|SECRET|TOKEN|API[_-]?KEY|ACCESS[_-]?KEY|PRIVATE[_-]?KEY|COOKIE|AUTHORIZATION|CREDENTIAL)[A-Z0-9_.-]*\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;]+)/i
      AUTH_LINE = /\b(AUTHORIZATION|COOKIE|SET-COOKIE)\s*:\s*[^\r\n]*/i
      QUERY_SECRET = /([?&](?:token|access_token|refresh_token|api_key|key|secret|password)=)[^&\s]+/i
      URL_CREDENTIAL = %r{(://[^/\s:@]+:)[^/@\s]+@}
      OPERATION_VERBS = /\A\s*(?:(?:please|can you|could you|would you|tolong)\s+)*(?:fix|repair|run|execute|check|test|deploy|redeploy|build|commit|push|audit|inspect|verify|scan|render|generate|create|update|remove|delete|migrate|restart|start|stop|publish|install|revert|rollback|preflight|finish|complete|implement|refactor|streamline|clean|optimize|analyse|analyze|assess|restore|jalankan|semak|baiki|uji|bina|kemas kini|padam)\b/i
      PRIVATE_COMMANDS = %w[documents memory read write ask chat email mail message forget pair].freeze
      PRIVATE_SHELL_COMMANDS = %w[cat less more head tail sed awk grep rg find env printenv set history].freeze

      Outcome = Struct.new(:url, :service, :error, keyword_init: true) do
        def success? = !url.to_s.empty?
      end

      def initialize(root: Master::REPO_ROOT, transport: nil, enabled: ENV.fetch("MASTER_LOG_PUBLISH", "1"))
        @root = File.expand_path(root.to_s)
        @transport = transport
        @enabled = enabled.to_s != "0"
      end

      def self.operation_request?(input)
        text = input.to_s.strip
        if text.start_with?("/")
          name = text[/\A\/([a-z][a-z0-9_-]*)/i, 1].to_s.downcase
          return false if PRIVATE_COMMANDS.include?(name)

          return true
        end
        if text.start_with?("!")
          command = text.delete_prefix("!").strip
          executable = command[/\A(?:sudo\s+)?([A-Za-z0-9._\/-]+)/, 1].to_s
          return false if PRIVATE_SHELL_COMMANDS.include?(File.basename(executable))

          return true
        end

        text.match?(OPERATION_VERBS)
      end

      def publish(operation:, status:, output:)
        return Outcome.new(error: :disabled) unless @enabled
        return Outcome.new(error: :visitor) if Fiber[:master_visitor] == true

        report = build_report(operation:, status:, output:)
        return Outcome.new(error: :empty) if report.empty?

        failures = []
        [
          [:pste_us, method(:upload_pste_us)],
          [:dpaste_org, method(:upload_dpaste_org)],
        ].each do |service, upload|
          begin
            url = upload.call(report, safe_title(operation))
            return Outcome.new(url:, service:)
          rescue StandardError => e
            failures << "#{service}=#{e.class}"
          end
        end

        Outcome.new(error: failures.join(","))
      rescue StandardError => e
        Outcome.new(error: e.class.name)
      end

      def build_report(operation:, status:, output:)
        label = sanitize(operation.to_s)[0, OPERATION_MAX_CHARS]
        outcome = %w[success failure changed inconclusive blocked cancelled].include?(status.to_s) ? status.to_s : "unknown"
        details = sanitize(output)
        report = [
          "MASTER operation log",
          "finished_utc: #{Time.now.utc.iso8601}",
          "operation: #{label.empty? ? "unspecified" : label}",
          "status: #{outcome}",
          "",
          details,
        ].join("\n")
        truncate(report)
      end

      def sanitize(value)
        text = value.to_s.scrub.gsub(ANSI, "")
        text = text.gsub(PRIVATE_KEY_BLOCK, "[PRIVATE KEY BLOCK REDACTED]")
        text = text.gsub(AUTH_LINE) { "#{$1}=[REDACTED]" }
        text = text.gsub(SENSITIVE_ASSIGNMENT) { "#{$1}[REDACTED]" }
        text = text.gsub(/\b(Bearer\s+)[A-Za-z0-9._+\/-]+/i, '\1[REDACTED]')
        text = text.gsub(QUERY_SECRET, '\1[REDACTED]')
        text = text.gsub(URL_CREDENTIAL, '\1[REDACTED]@')
        text = Master::Ground::Redactor.text(text)
        text = text.gsub(home, "$HOME") unless home.empty? || home == "/"
        text = text.gsub(@root, "$REPO") unless @root.empty?
        home = File.expand_path(Dir.home)
        text
      rescue StandardError
        "[diagnostic redaction failed]"
      end

      def truncate(text)
        return text if text.bytesize <= MAX_BYTES

        "#{text.byteslice(0, MAX_BYTES).to_s.scrub}\n[operation log truncated at #{MAX_BYTES} bytes]"
      end

      private

      def safe_title(operation)
        label = sanitize(operation.to_s).gsub(/\s+/, " ").strip
        "MASTER operation: #{label.empty? ? "completed" : label[0, 80]}"
      end

      def upload_pste_us(report, title)
        uri = URI("https://pste.us/api/v1/pastes")
        payload = JSON.generate(
          "content" => report,
          "title" => title,
          "language" => "text",
          "expires_in" => EXPIRY,
        )
        response = post(uri, payload, {
          "Content-Type" => "application/json",
          "Accept" => "application/json",
        })
        require_success!(response)
        parsed = JSON.parse(response.body.to_s)
        raise IOError, "paste service rejected the report" unless parsed["ok"] == true

        data = parsed["data"].is_a?(Hash) ? parsed["data"] : {}
        checked_url(data["url"] || data["paste_url"], "pste.us")
      end

      def upload_dpaste_org(report, title)
        uri = URI("https://dpaste.org/api/")
        body = URI.encode_www_form(
          "content" => report,
          "lexer" => "text",
          "title" => title,
          "expires" => "86400",
          "format" => "url",
        )
        response = post(uri, body, {
          "Content-Type" => "application/x-www-form-urlencoded",
          "Accept" => "text/plain",
        })
        require_success!(response)
        candidate = response["location"].to_s.strip
        candidate = response.body.to_s.strip if candidate.empty?
        checked_url(candidate, "dpaste.org")
      end

      def post(uri, body, headers)
        return @transport.call(uri:, body:, headers:) if @transport

        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = body
        http = Net::HTTP.new(uri.host, uri.port, nil)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.write_timeout = WRITE_TIMEOUT if http.respond_to?(:write_timeout=)
        http.start { |connection| connection.request(request) }
      end

      def require_success!(response)
        code = response.code.to_i
        raise IOError, "paste service HTTP #{code}" unless code.between?(200, 299)
      end

      def checked_url(value, expected_host)
        uri = URI.parse(value.to_s)
        unless uri.is_a?(URI::HTTPS) && uri.host.to_s.downcase == expected_host &&
               uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
          raise IOError, "paste service returned an unexpected URL"
        end
        uri.to_s
      rescue URI::InvalidURIError
        raise IOError, "paste service returned an invalid URL"
      end
    end
  end
end
