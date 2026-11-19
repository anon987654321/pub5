# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "../../../OPENBSD/lib/secret_redaction"

module Master
  module Fix
    # Publishes the /fix run's logs to a paste sink after each terminal event,
    # so a run that outlived its operator's terminal still has a public,
    # shareable record.
    #
    # Safety contract, in order:
    #   1. Fail-soft: any publication error is swallowed and recorded as an
    #      outcome receipt field; a paste outage never blocks or fails a run.
    #   2. Redacted: the published body passes through SecretRedaction and the
    #      residue audit refuses the upload if any secret-shaped line survives
    #      — an unredacted log never leaves the box.
    #   3. Bounded: at most MAX_BYTES of the most recent log lines are sent;
    #      a giant run publishes its tail with a truncation marker, never a
    #      partial middle.
    #   4. Opt-out: PUB5_FIX_LOG_PUBLISH=0 (or off/false) disables it; the
    #      default is on, and a missing token falls back to the keyless sink.
    #      =1 (or on/true) forces it on. Under MASTER_IN_PROOF=1 (the test
    #      suite) the default flips to off so a proof never egresses; the
    #      explicit =1 still wins.
    #
    # Sinks, tried in order:
    #   - GitHub Gist when GITHUB_TOKEN (or GH_TOKEN) is in the environment:
    #     a secret gist named for the run id.
    #   - ix.io keyless otherwise.
    #
    # The outcome is a small hash recorded on the terminal event's evidence:
    #   { sink: "gist"|"ix.io", url: ..., redacted: true, truncated: bool }
    #   or { sink: nil, skipped: "reason" } / { sink: nil, error: "class: message" }
    class LogPublication
      MAX_BYTES = 512 * 1024
      TIMEOUT = 20
      GIST_API = "https://api.github.com/gists".freeze
      IX_IO = "https://ix.io".freeze
      DISABLE_VALUES = %w[0 off false no].freeze
      ENABLE_VALUES = %w[1 on true yes].freeze

      Result = Struct.new(:sink, :url, :redacted, :truncated, :skipped, :error, keyword_init: true) do
        def to_h
          { sink: sink, url: url, redacted: redacted, truncated: truncated,
            skipped: skipped, error: error }.compact
        end
      end

      def self.publish(run_id:, log_text:, env: ENV, http: nil)
        new(http:).publish(run_id:, log_text:, env:)
      end

      def initialize(http: nil)
        @http = http || method(:post)
      end

      def publish(run_id:, log_text:, env: ENV)
        setting = env["PUB5_FIX_LOG_PUBLISH"].to_s.downcase
        if DISABLE_VALUES.include?(setting)
          return Result.new(skipped: "PUB5_FIX_LOG_PUBLISH disables publication")
        end
        if env["MASTER_IN_PROOF"].to_s == "1" && !ENABLE_VALUES.include?(setting)
          return Result.new(skipped: "MASTER_IN_PROOF suite; set PUB5_FIX_LOG_PUBLISH=1 to force publication")
        end

        # Redact before byte-bounding: slicing the tail first can remove a
        # secret's key name and leave its value looking like ordinary text.
        full_text = log_text.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        redacted = ::SecretRedaction.redact(full_text)
        body, truncated = bounded(redacted)
        residue = ::SecretRedaction.residue(body)
        unless residue.empty?
          return Result.new(skipped: "residue audit refused publication: #{residue.first(3).join('; ')}")
        end

        if (token = env["GITHUB_TOKEN"].to_s.empty? ? env["GH_TOKEN"].to_s : env["GITHUB_TOKEN"].to_s) && !token.empty?
          gist(run_id:, body: redacted, token:, truncated:)
        else
          ix(run_id:, body: redacted, truncated:)
        end
      rescue StandardError => error
        Result.new(error: "#{error.class}: #{error.message}")
      end

      private

      def bounded(text)
        return [text, false] if text.bytesize <= MAX_BYTES

        tail = text.byteslice(-MAX_BYTES, MAX_BYTES) || text
        ["[log truncated to the last #{MAX_BYTES} bytes]\n#{tail}", true]
      end

      def gist(run_id:, body:, token:, truncated:)
        payload = {
          description: "pub5 /fix run #{run_id}#{truncated ? ' (truncated tail)' : ''}",
          public: false,
          files: { "fix-#{run_id}.log" => { content: body } },
        }
        response = @http.call(GIST_API, payload, {
          "Authorization" => "Bearer #{token}",
          "Accept" => "application/vnd.github+json",
          "X-GitHub-Api-Version" => "2022-11-28",
        })
        url = response.dig("html_url").to_s
        raise "gist upload returned no url (status #{response["__status"] || 'unknown'})" if url.empty?

        Result.new(sink: "gist", url:, redacted: true, truncated:)
      end

      def ix(run_id:, body:, truncated:)
        payload = "f:1=#{"pub5 /fix #{run_id}#{truncated ? ' (truncated tail)' : ''}"}\n\n#{body}"
        response = @http.call(IX_IO, payload, {}, form: true)
        url = response.is_a?(String) ? response.strip : response["body"].to_s.strip
        raise "ix.io upload returned no url" unless url.start_with?("http")

        Result.new(sink: "ix.io", url:, redacted: true, truncated:)
      end

      def post(url, payload, headers, form: false)
        uri = URI(url)
        request =
          if form
            Net::HTTP::Post.new(uri).tap do |req|
              req.set_form_data("f:1" => payload)
            end
          else
            Net::HTTP::Post.new(uri).tap do |req|
              req["Content-Type"] = "application/json"
              headers.each { |key, value| req[key] = value }
              req.body = JSON.generate(payload)
            end
          end
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                   open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |conn| conn.request(request) }
        if form
          response.body.to_s
        else
          parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
          parsed = { "body" => response.body.to_s } unless parsed.is_a?(Hash)
          parsed["__status"] = response.code.to_i
          parsed
        end
      end
    end
  end
end
