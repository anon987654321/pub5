# frozen_string_literal: true

require "json"
require "tempfile"
require "timeout"
require_relative "../../io/exec"
require_relative "cli_usage"

module Master
  module Review
    class LLMDispatcher
      # Signed-in command-line clients declared by MASTER's CLI lane catalogue.
      module CliSender
        include CliUsage

        CLI_LANE_TIMEOUT_S = 300

        private

        def cli_lane_model?(model_id) = cli_lanes.key?(model_id.to_s.split(":", 2).first)

        # A lane from models.yml: its ask arguments with the prompt and reply
        # file filled in, the model flag unless the model is auto, the prompt on
        # stdin when the arguments do not carry it, and the reply read from the
        # file when the CLI wrote one.
        def send_cli_lane(selected_model, messages, sys:)
          name, model = selected_model.to_s.split(":", 2)
          prompt = [sys.to_s, text_prompt_for(messages)].reject(&:empty?).join("\n\n---\n\n")
          Tempfile.create(["master_#{name}", ".txt"]) do |reply_file|
            ask_cli_lane(name, model, prompt, reply_file.path)
          end
        end

        def ask_cli_lane(name, model, prompt, reply_path)
          lane = cli_lanes.fetch(name)
          if (path_env = lane["model_path_env"])
            path = ENV[path_env].to_s
            return Result.err("#{name}: set #{path_env} to a readable local GGUF file", category: :no_api_key) if
              path.empty? || !File.file?(path) || !File.readable?(path)
          end

          out, err, status = with_cli_slot(name) do
            capture3_with_timeout(CLI_LANE_TIMEOUT_S, cli_binary(lane["binary"]),
                                  *cli_lane_args(lane, model, prompt, reply_path),
                                  stdin_data: cli_lane_stdin(lane, prompt))
          end

          result = cli_lane_result(name, out, err, status, reply_path)
          record_estimated_cli_usage(model: "#{name}:#{model}", prompt:, reply: result.value!) if result.ok?
          result
        rescue Timeout::Error
          Result.err("#{name}: timed out after #{PassClock.call_deadline(CLI_LANE_TIMEOUT_S)}s", category: :timeout)
        rescue StandardError => e
          Result.err("#{name}: #{e.message}", category: :provider_error)
        end

        def cli_lane_args(lane, model, prompt, reply_path)
          model_path = ENV[lane["model_path_env"].to_s].to_s
          args = Array(lane["ask"]).map do |arg|
            arg.to_s.gsub("%{prompt}", prompt).gsub("%{reply_file}", reply_path).gsub("%{model_path}", model_path)
          end
          lane["model_flag"] && model.to_s != "auto" ? args + [lane["model_flag"], model] : args
        end

        def cli_lane_stdin(lane, prompt)
          Array(lane["ask"]).any? { |arg| arg.to_s.include?("%{prompt}") } ? nil : prompt
        end

        # A failure carries the CLI's last words, which is where codex and grok
        # say a plan is spent or a session signed out.
        def cli_lane_result(name, out, err, status, reply_path)
          reply = File.file?(reply_path) ? File.read(reply_path).strip : ""
          reply = out.to_s.strip if reply.empty?
          return Result.ok(reply) if status.success? && !reply.empty?

          said = cli_lane_complaint(out, err) || "exit #{status.exitstatus}"
          Result.err("#{name}: #{said}", category: :provider_error)
        end

        # Prefer stderr diagnostics; otherwise extract a textual error from
        # structured stdout or use the final plain-text lines.
        def cli_lane_complaint(out, err)
          out = out.to_s.strip
          said = err.to_s.strip
          return if said.empty? && out.empty?

          return said.lines.last(2).join.strip unless said.empty?
          return cli_event_complaint(out) if json_stream?(out)

          out.lines.last(2).join.strip
        end

        def json_stream?(text) = text.lines.any? { |line| line.lstrip.start_with?("{") }

        # The text a json stdout event gives as the reason: an error's own message, or the
        # result event of a run that ended badly. nil when stdout offers no such field.
        def cli_event_complaint(out)
          out.lines.reverse_each do |line|
            next unless line.lstrip.start_with?("{")

            event = JSON.parse(line)
            next unless event.is_a?(Hash)

            fields = [event["error"], (event["result"] if event["is_error"]), event["message"]]
            said = fields.grep(String).map(&:strip).find { |text| !text.empty? }
            return said if said
          rescue JSON::ParserError
            next
          end
          nil
        end

        def with_cli_slot(name = nil)
          lane = name && cli_lanes[name]
          slots = lane && lane["kind"] == "local" ? LOCAL_CLI_SLOTS : lane_slots(name)
          slots.pop
          yield
        ensure
          slots << true if slots
        end

        def cli_binary(binary)
          home = File.expand_path("~/.local/bin/#{binary}")
          File.executable?(home) ? home : binary.to_s
        end

        def cli_lanes = Master.cli_lanes

        # A lane whose program is not installed refuses at once rather than
        # failing inside a subprocess that never starts: ENOENT reads as a
        # provider error, and the chain slept through its backoff before
        # walking on. Absent is permanent, so the chain walks on at once.
        def send_agy_cli(model_alias, messages, sys:, stream: false, &blk)
          agy_bin = find_agy_bin
          return Result.err("agy: no agy on PATH", category: :no_api_key) unless agy_bin

          result = with_cli_slot { agy_cli_call(agy_bin, model_alias, messages, sys, stream, &blk) }
          record_estimated_cli_usage(model: "agy:#{model_alias}", prompt: "#{sys}#{text_prompt_for(messages)}",
                                     reply: result.value!) if result.ok?
          result
        end

        def agy_cli_call(agy_bin, model_alias, messages, sys, stream, &blk)
          prompt = text_prompt_for(messages)
          full_prompt = sys && !sys.empty? ? "#{sys}\n\n---\n\n#{prompt}" : prompt
          args = [agy_bin, "-p", full_prompt, "--output-format", "text"]
          args += ["--model", model_alias] if model_alias && !["", "auto", "agy"].include?(model_alias)
          timeout_s = agy_cli_timeout_s
          out, err, status = capture3_with_timeout(timeout_s, *args)
          return Result.err("agy: #{err.strip}", category: :provider_error) unless status.success?

          said = out.to_s.strip
          return Result.err("agy: exited successfully without a reply", category: :provider_error) if said.empty?

          blk&.call(said) if stream && block_given?
          Result.ok(said)
        rescue Timeout::Error
          Result.err("agy: timed out after #{PassClock.call_deadline(timeout_s)}s", category: :timeout)
        rescue StandardError => e
          Result.err("agy: #{e.message}", category: :provider_error)
        end

        def find_agy_bin
          configured = ENV["AGY_BIN"]
          return configured if configured && File.file?(configured) && File.executable?(configured)

          Master::Io::Exec.which("agy", prefer: [File.expand_path("~/.local/bin")])
        end

        def agy_cli_timeout_s
          Integer(ENV.fetch("MASTER_AGY_CLI_TIMEOUT", AGY_CLI_TIMEOUT_S.to_s))
        rescue ArgumentError
          AGY_CLI_TIMEOUT_S
        end

        CLI_SLOTS = Integer(ENV.fetch("MASTER_CLI_SLOTS", 2)).then { |n| SizedQueue.new(n).tap { |queue| n.times { queue << true } } }
        LOCAL_CLI_SLOTS = SizedQueue.new(1).tap { |queue| queue << true }
        LANE_SLOTS_MUTEX = Mutex.new
        LANE_SLOTS = {}

        # A lane may declare `slots:` in models.yml cli_lanes to hold its own
        # concurrency ceiling. Three stream workers plus the lane probe and
        # the consensus jury pushed the z-ai gateway into 429s twice in one
        # session (2026-11-17); the lane, not the operator, knows what its
        # provider tolerates. An undeclared lane rides the shared CLI_SLOTS.
        def lane_slots(name)
          declared = Integer(cli_lanes.dig(name, "slots").to_s, exception: false)
          return CLI_SLOTS unless declared&.positive?

          LANE_SLOTS_MUTEX.synchronize do
            LANE_SLOTS[name] ||= SizedQueue.new(declared).tap { |queue| declared.times { queue << true } }
          end
        end

        # The sanctioned runner owns stream draining, child tracking and
        # process-group cleanup.
        def capture3_with_timeout(timeout_s, *cmd, env: {}, **opts)
          opts.delete(:on_stdout) if opts[:on_stdout].nil?
          timeout_s = PassClock.call_deadline(timeout_s)
          out, err, status = Master::Io::Exec.capture3(env, *cmd, timeout: timeout_s, raise_on_timeout: true, **opts)
          [out.to_s.dup.force_encoding(Encoding::UTF_8).scrub, err.to_s.dup.force_encoding(Encoding::UTF_8).scrub, status]
        rescue Master::Io::Exec::TimeoutError
          raise Timeout::Error
        end

      end
    end
  end
end
