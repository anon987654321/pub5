# frozen_string_literal: true

module Master
  module Voice
    class Narrator
      # Asks the cheapest live lane of the configured tier for the next beat.
      # Raises Unavailable when no lane can answer; the narrator then speaks
      # from its template and tries again later.
      class LaneWriter
        Unavailable = Class.new(StandardError)

        # `claude --print` inherits these two from a Claude Code session and
        # hangs; unset, it answers in seconds. Text only, no tools and none of
        # the operator's hooks: a narrator must not be able to touch the tree.
        SESSION_ENV = { "CLAUDECODE" => nil, "CLAUDE_CODE_ENTRYPOINT" => nil }.freeze
        TEXT_ONLY = ["--tools", "", "--strict-mcp-config", "--settings", '{"disableAllHooks":true}'].freeze
        UNSUPPORTED_LANES = %w[grok-cli codex-cli agy web-chat].freeze
        REFUSAL_PREFIX = /\A(?:you['’]ve hit your (?:session|usage|weekly|daily|message) limit|you exceeded your current quota|individual quota (?:reached|exceeded)|quota (?:reached|exceeded|exhausted)|rate limit exceeded|HTTP\s*429|(?:401|403)\s+unauthori[sz]ed|unauthori[sz]ed|invalid api[ _-]?key|authentication (?:failed|required)|please run \/login)/i.freeze

        def initialize(config, lanes: Master::Io::LaneSelection, runner: Master::Io::Exec)
          @config = config
          @lanes = lanes
          @runner = runner
        end

        def call(system:, prompt:, max_tokens:)
          model = pick or raise Unavailable, "no live #{@config["lane_tier"]} lane"
          reply = model.start_with?("claude-cli:") ? via_claude_cli(model, system, prompt) : via_ruby_llm(model, system, prompt, max_tokens)
          text = reply.to_s.strip
          if text.empty?
            if model.start_with?("claude-cli:")
              lane = Master::Io::LaneSilence.lane_of(model)
              if Master::Io::LaneSilence.record(false, lane, reason: "narration returned an empty reply")
                Master::Trace::Dmesg.once("llm0-#{lane}", Master::Io::LaneSilence.message(lane))
              end
            end
            raise Unavailable, "#{model} answered nothing"
          end

          Master::Io::LaneSilence.record(true, Master::Io::LaneSilence.lane_of(model)) if model.start_with?("claude-cli:")
          text
        end

        def pick
          tier = @lanes.tier(@config.fetch("lane_tier", "fast"))
          @lanes.order(tier).find { |id| supported?(id) && @lanes.alive?(id) }
        end

        private

        def supported?(id) = UNSUPPORTED_LANES.none? { |lane| id.start_with?(lane) }

        def via_claude_cli(model, system, prompt)
          claude = Master::Io::Exec.cli_binary("claude") || "claude"
          timeout_s = Float(@config.fetch("model_timeout_s", 20))
          out, err, status = @runner.capture3(
            SESSION_ENV, claude, "--print", "--model", model.split(":", 2).last, *TEXT_ONLY, "--system-prompt", system,
            stdin_data: prompt, timeout: timeout_s
          )
          combined = [out, err].filter_map { |value| value.to_s.strip unless value.to_s.strip.empty? }.join("\n")
          Master::Trace::Dmesg.detail(
            "voice", "claude-cli output: #{Master::Ground::Redactor.text(combined)}"
          ) if !combined.empty? && Master::Trace::Dmesg.detail_enabled?

          # A limit or login refusal can arrive with exit status 1. Record the
          # provider's words before interpreting the exit code. On exit 0, only
          # accept a short, provider-shaped refusal at the beginning of stdout;
          # an ordinary narration that quotes a quota phrase is still an answer.
          refusal = status.success? ? provider_refusal_output?(combined) : !combined.empty?
          refusal_text = combined
          if refusal && Master::Io::LaneQuota.note(model, refusal_text)
            reason = Master::Io::LaneQuota.report_for(model) || "claude-cli quota or login refusal"
            raise Unavailable, reason
          end

          lane = Master::Io::LaneSilence.lane_of(model)
          unless status.success?
            evidence = Master::Execution::Contract.diagnostic_fields(combined)
            detail = if combined.empty?
                       "no stdout or stderr"
                     else
                       "diagnostic #{evidence.fetch(:error_digest)[0, 12]} (#{evidence.fetch(:error_bytes)} bytes)"
                     end
            if Master::Io::LaneSilence.record(false, lane, reason: detail)
              Master::Trace::Dmesg.once("llm0-#{lane}", Master::Io::LaneSilence.message(lane))
            end
            raise Unavailable, "claude-cli exited #{status.exitstatus.inspect}; #{detail}"
          end

          out
        rescue Timeout::Error
          lane = Master::Io::LaneSilence.lane_of(model)
          Master::Io::LaneSilence.silence(lane, reason: "narration call timed out after #{timeout_s}s")
          Master::Trace::Dmesg.once("llm0-#{lane}", Master::Io::LaneSilence.message(lane))
          raise Unavailable, "claude-cli timed out after #{timeout_s}s; #{lane} skipped for #{Master::Io::LaneSilence::SILENCE_COOLOFF_S / 60} minutes"
        end

        def provider_refusal_output?(text)
          lines = text.to_s.lines.map(&:strip).reject(&:empty?)
          return false if lines.empty? || lines.size > 3

          REFUSAL_PREFIX.match?(lines.first)
        end

        def via_ruby_llm(model, system, prompt, max_tokens)
          require "ruby_llm"
          chat = RubyLLM.chat(model:).with_instructions(system)
          chat = chat.with_params(max_tokens:) if chat.respond_to?(:with_params)
          chat.ask(prompt).content
        end
      end
    end
  end
end
