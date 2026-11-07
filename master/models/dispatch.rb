# frozen_string_literal: true

require "base64"
require "json"
require_relative "catalog"
require_relative "lanes"
require_relative "router"
require_relative "gate"

module Models
  # The one door every model call passes: route, pace, ask each lane in turn
  # until one answers, and keep the lane breaker and the ledger true. HTTP
  # providers go through World#llm (core writes their tokens and cost);
  # command-line lanes go through World#exec, and their spend is appended to
  # the same ledger here, so a run's budget is a sum over one file whichever
  # lane it used. Before this, pub4's /fix heartbeat read "tokens = 0" for a
  # whole claude-cli run and no spend cap could trip on its busiest lane.
  class Dispatch
    Reply = Data.define(:text, :model, :tokens_in, :tokens_out, :cost_usd, :seconds)

    # One lane's failure, classified for the breaker (Lanes#failed).
    class LaneError < StandardError
      attr_reader :category

      def initialize(message, category = :error)
        @category = category
        super(message)
      end
    end

    # Every candidate failed or was passed over; attempts says why, per model.
    class Exhausted < StandardError
      attr_reader :attempts

      def initialize(attempts)
        @attempts = attempts
        super(attempts.empty? ? "no lane reaches a model" : attempts.map { |m, why| "#{m}: #{why}" }.join("; "))
      end
    end

    # The subscription's own limit answers on stdout and exits 0. Taken as a
    # reply, "You've hit your session limit - resets 4:30pm" was proposed as a
    # fix two hundred times in one pub4 /fix run. It is a quota.
    CLAUDE_LIMIT = /\A\s*(?:You've hit your \w*\s*limit|Claude (?:AI )?usage limit reached)/i
    # A lane answers in text and nothing else. Left its tools, `claude --print`
    # edited files and committed inside pub4's /fix worktree on its own; the
    # operator's Claude Code hooks are not MASTER's either.
    CLAUDE_TEXT_ONLY = ["--tools", "", "--strict-mcp-config", "--settings", '{"disableAllHooks":true}'].freeze
    # A child that inherits a Claude Code session hangs; one that inherits an
    # API key bills the key instead of the subscription login.
    CLAUDE_UNSET = %w[CLAUDECODE CLAUDE_CODE_ENTRYPOINT ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN].freeze
    CLAUDE_USAGE = %w[input_tokens cache_read_input_tokens cache_creation_input_tokens].freeze
    CLI_REPLY = "log/master/cli-reply.txt"
    CHARS_PER_TOKEN = 4

    attr_reader :router, :lanes

    # pace_load: let a loaded host come down before each call (Gate). A /fix
    # run wants it; a person at the prompt wants the answer, so the REPL and
    # `ask` wait only for a pinned lane's cool-off.
    def self.build(world, knobs:, say: ->(_line) {}, deadline: nil, pace_load: false)
      catalog = Catalog.new
      lanes = Lanes.new(catalog:, store: Lanes::Store.new(world))
      router = Router.new(catalog:, lanes:, knobs:)
      load = pace_load ? -> { Gate.host_load(world) } : -> {}
      gate = Gate.new(lanes:, load:, say:, deadline:)
      new(world:, catalog:, lanes:, router:, gate:, knobs:, say:)
    end

    # bin_dir: where the lane binaries live when not on PATH (a test's stubs).
    def initialize(world:, catalog:, lanes:, router:, gate:, knobs:, say: ->(_line) {}, bin_dir: nil)
      @world = world
      @catalog = catalog
      @lanes = lanes
      @router = router
      @gate = gate
      @knobs = knobs
      @say = say
      @bin_dir = bin_dir
    end

    # messages: earlier turns as [{role:, content:}], oldest first.
    def ask(prompt, system: nil, task: nil, messages: [], max_tokens: 4096)
      refuse_spent!
      chain = @router.chain(task || @router.classify(prompt))
      @gate.before_call(chain.select { |m| @lanes.cooling?(m) }.size == chain.size ? chain : [])
      messages = [*messages, { role: "user", content: prompt.to_s }]
      attempts = []
      chain.each do |model|
        if (why = @lanes.verdict(model))
          attempts << [model, why]
          next
        end

        return answer(model, messages, system, max_tokens)
      rescue LaneError => e
        attempts << [model, e.message]
        @say.call(@lanes.failed(model, e.message, category: e.category)) unless e.category == :absent
      end
      raise Exhausted, attempts
    end

    # A browser observation is a multimodal turn, not an image-generation
    # request. It uses only image-capable HTTP lanes on the registry's vision
    # route; CLI fallbacks never receive a path or a base64 blob as plain text.
    def ask_with_image(prompt, image:, system: nil, messages: [], max_tokens: 4096)
      refuse_spent!
      chain = @router.chain("vision").select { |model| image_lane?(model) }
      raise Exhausted, [["vision", "no reachable image-capable HTTP lane"]] if chain.empty?

      @gate.before_call(chain.select { |model| @lanes.cooling?(model) }.size == chain.size ? chain : [])
      attempts = []
      chain.each do |model|
        if (why = @lanes.verdict(model))
          attempts << [model, why]
          next
        end

        begin
          content = [*messages, { role: "user", content: image_content(model, prompt, image) }]
          return answer(model, content, system, max_tokens)
        rescue LaneError => e
          attempts << [model, e.message]
          @say.call(@lanes.failed(model, e.message, category: e.category)) unless e.category == :absent
        end
      end
      raise Exhausted, attempts
    end

    private

    MAX_IMAGE_BYTES = 2 * 1024 * 1024
    PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze

    def image_lane?(model)
      return false unless @catalog.kind(model) == :http

      protocol = @catalog.provider(model)["protocol"]
      return false unless %w[openai anthropic].include?(protocol)

      patterns = @catalog.models.dig("vision_families", "reads_images").to_a
      patterns.any? { |pattern| @catalog.model_name(model).match?(Regexp.new(pattern)) }
    end

    def image_content(model, prompt, image)
      image = image.to_h.transform_keys(&:to_sym)
      media_type = image.fetch(:media_type).to_s
      data = image.fetch(:data).to_s
      raise ArgumentError, "only PNG screenshots are accepted" unless media_type == "image/png"

      bytes = Base64.strict_decode64(data)
      raise ArgumentError, "screenshot is not a PNG image" unless bytes.start_with?(PNG_SIGNATURE)
      raise ArgumentError, "screenshot exceeds #{MAX_IMAGE_BYTES} bytes" if bytes.bytesize > MAX_IMAGE_BYTES

      case @catalog.provider(model).fetch("protocol")
      when "anthropic"
        [
          { type: "text", text: prompt.to_s },
          { type: "image", source: { type: "base64", media_type:, data: } }
        ]
      when "openai"
        [
          { type: "text", text: prompt.to_s },
          { type: "image_url", image_url: { url: "data:#{media_type};base64,#{data}" } }
        ]
      else
        raise ArgumentError, "unsupported image protocol"
      end
    rescue KeyError, ArgumentError => e
      raise ArgumentError, "invalid browser screenshot: #{e.message}"
    end

    def answer(model, messages, system, max_tokens)
      started = now
      refuse_spent!
      text, tokens_in, tokens_out, cost = case @catalog.kind(model)
                                          when :claude then claude(model, messages, system)
                                          when :cli then cli(model, messages, system)
                                          else http(model, messages, system, max_tokens)
                                          end
      @lanes.succeeded(model)
      Reply.new(text:, model:, tokens_in:, tokens_out:, cost_usd: cost, seconds: (now - started).round(1))
    end

    def http(model, messages, system, max_tokens)
      provider = @catalog.lane_of(model)
      reply = @world.llm(provider:, model: @catalog.model_name(model), messages:, system:, max_tokens:)
      [reply.text, reply.tokens_in, reply.tokens_out, reply.cost_usd]
    rescue Core::Refusal => e
      raise unless e.verb == :llm

      raise LaneError.new(e.message, http_category(e.message))
    rescue Timeout::Error, IOError, SystemCallError, SocketError => e
      raise LaneError.new("#{provider}: #{e.class}: #{e.message}", :timeout)
    end

    # Offline and budget refusals stop the whole call, not one lane: no
    # other lane would be allowed either.
    def http_category(message)
      raise Core::Refusal.new(:llm, "models", message.sub(/\Arefused llm \S+: /, "")) if
        message.match?(/PUB5_OFFLINE|run budget/)

      case message[/HTTP (\d{3})/, 1].to_i
      when 401, 403 then :dead
      when 402 then :quota
      when 0 then :absent # no key, or not declared: an operator fact, not a lane failure
      else :error
      end
    end

    def claude(model, messages, system)
      argv = ["claude", "--print", "--model", @catalog.model_name(model), *CLAUDE_TEXT_ONLY, "--output-format", "json"]
      argv += ["--system-prompt", system] if system && !system.empty?
      run = exec_lane(model, argv, transcript(messages), unset: CLAUDE_UNSET)
      event = result_event(run.out)
      text = event ? event["result"].to_s : run.out.strip
      raise LaneError.new("claude-cli: #{text.lines.first.to_s.strip}", :quota) if text.match?(CLAUDE_LIMIT)
      raise LaneError, "claude-cli: #{complaint(run) || 'error result'}" if event.nil? || event["is_error"] || text.empty?

      usage = event["usage"].is_a?(Hash) ? event["usage"] : {}
      tokens_in = CLAUDE_USAGE.sum { |key| usage[key].to_i }
      tokens_out = usage["output_tokens"].to_i
      # The CLI's own total_cost_usd: what the tokens cost at API prices. A
      # subscription bills none of it in money but spends its quota in
      # proportion, so the run's dollar cap is the quota's proxy here.
      cost = event["total_cost_usd"].is_a?(Numeric) ? event["total_cost_usd"].to_f : nil
      record(model, tokens_in:, tokens_out:, cost_usd: cost, subscription: true)
      [text.strip, tokens_in, tokens_out, cost]
    end

    # A lane from registry/models.yml cli_lanes (or agy): its ask arguments
    # with the prompt and reply file filled in, the model flag unless the model
    # is auto, the prompt on stdin when the arguments do not carry it.
    def cli(model, messages, system)
      lane = @catalog.cli_lane(model) or raise LaneError.new("#{model}: no cli_lanes row", :absent)
      prompt = [system.to_s, transcript(messages)].reject(&:empty?).join("\n\n---\n\n")
      reply_file = File.join(@world.manifest.root, CLI_REPLY)
      @world.write(CLI_REPLY, "", mode: 0o600)
      args = lane.fetch("ask").map { |a| a.gsub("%{prompt}", prompt).gsub("%{reply_file}", reply_file) }
      name = @catalog.model_name(model)
      args += [lane["model_flag"], name] if lane["model_flag"] && name != "auto"
      stdin = lane.fetch("ask").any? { |a| a.include?("%{prompt}") } ? nil : prompt
      run = exec_lane(model, [lane.fetch("binary"), *args], stdin)
      text = @world.read(CLI_REPLY).strip
      text = run.out.strip if text.empty?
      raise LaneError, "#{@catalog.lane_of(model)}: no reply" if text.empty?

      # No usage on these lanes: an estimate from characters, marked as one,
      # so the calls still count; cost stays unmeasured, never zero.
      tokens_in = prompt.size / CHARS_PER_TOKEN
      tokens_out = text.size / CHARS_PER_TOKEN
      record(model, tokens_in:, tokens_out:, cost_usd: nil, estimated: true)
      [text, tokens_in, tokens_out, nil]
    end

    def exec_lane(model, argv, stdin, unset: [])
      lane = @catalog.lane_of(model)
      timeout = @knobs.fetch("PUB5_MODEL_TIMEOUT")
      argv = [File.join(@bin_dir, argv.first), *argv.drop(1)] if @bin_dir
      run = @world.exec(*argv, stdin:, timeout:, unset:)
      raise LaneError.new("#{lane}: no #{argv.first} on PATH", :dead) if run.status.nil?
      raise LaneError.new("#{lane}: no answer in #{timeout}s", :timeout) if run.timed_out
      raise LaneError, "#{lane}: #{complaint(run) || "exit #{run.status.exitstatus} with nothing on either stream"}" unless run.ok?

      run.out.force_encoding(Encoding::UTF_8).scrub
      run
    rescue Core::Refusal => e
      raise LaneError.new(e.message, :absent)
    end

    def record(model, **fields)
      @world.ledger.append(:llm, provider: @catalog.lane_of(model), model: @catalog.model_name(model), status: 0, **fields)
    end

    # The final result event of a json run, or nil when stdout carried none.
    def result_event(out)
      out.lines.reverse_each do |line|
        next unless line.lstrip.start_with?("{")

        event = JSON.parse(line)
        return event if event.is_a?(Hash) && event["type"] == "result"
      rescue JSON::ParserError
        next
      end
      nil
    end

    # A CLI that dies says why in its last two lines, on either stream.
    def complaint(run)
      said = [run.err, run.out].map { |t| t.to_s.dup.force_encoding(Encoding::UTF_8).scrub.strip }.reject(&:empty?).last
      said&.lines&.last(2)&.join&.strip
    end

    def transcript(messages)
      return messages.last[:content].to_s if messages.size == 1

      messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
    end

    # Core checks the budget before an HTTP call; a CLI lane is checked here
    # against the same ledger, and PUB5_OFFLINE refuses it too.
    def refuse_spent!
      raise Core::Refusal.new(:llm, "models", "PUB5_OFFLINE is set") if @knobs.fetch("PUB5_OFFLINE")

      budget = @knobs.fetch("PUB5_RUN_BUDGET_USD") or return
      spent = @world.ledger.spend.fetch("cost_usd")
      raise Core::Refusal.new(:llm, "models", "run budget #{budget} USD spent (#{spent})") if spent >= budget
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
