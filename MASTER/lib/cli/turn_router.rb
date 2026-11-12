# frozen_string_literal: true

require "shellwords"
require_relative "../io/media_intent"
require_relative "operator_intent"

module Master
  module CLI
    # TurnRouter — one entry for agent work: plain language → Fold, slash → command_registry.
    module TurnRouter
      module_function

      # Chained elsif nests one IfNode inside the previous one's else-branch,
      # so a 6-way route chain reads flat but is 6 deep in the AST. Guard
      # clauses keep each check a standalone, unnested IfNode.
      def call(message:, container:, felt_sense: nil, on_turn: nil, on_chunk: nil, image: nil, cancellation: nil)
        text = message.to_s.strip
        return Master::Result.err("empty message", category: :validation) if text.empty?
        if visitor? && text.start_with?("/") && !visitor_pair_redemption?(text)
          return Master::Result.err("slash commands are not available to visitors", category: :policy)
        end
        return dispatch_slash(rewrite_slash(text), container:, felt_sense:, on_turn:, cancellation:) if text.start_with?("/")

        # Visitors (no web token — i.e. the open internet on ai.brgen.no) get the
        # conversational path only. Everything below this line can reach real
        # capability: infer_operator_command *reconstructs* a slash command from
        # plain English, which defeats the leading-"/" block in
        # chat_controller#message, and run_fold reaches Core::World#do_exec,
        # whose argv/env are model-chosen. Fiber[:master_visitor] previously
        # gated only the advertised LLM tool list (tool_registry.rb), never the
        # Fold or the command registry.
        #
        # MediaIntent used to sit above this check. "generate a photo" / "make me
        # a beat" / a VHS look on a path then ran replicate/dilla/postpro as the
        # Falcon user and wrote under ~.
        return casual_reply(text, container:, felt_sense:, on_chunk:, image:) if visitor?
        if document_archive_request?(text)
          return dispatch_slash("/documents analyze #{document_archive_args(text)}", container:, felt_sense:, on_turn:, cancellation:)
        end
        if text.match?(FIX_COMMAND)
          return dispatch_slash(rewrite_slash("/#{text}"), container:, felt_sense:, on_turn:, cancellation:)
        end
        proposal = OperatorIntent.new(
          root: (Master::REPO_ROOT if defined?(Master::REPO_ROOT)) || container.fetch(:root, Dir.pwd),
          agent: container[:agent],
          event_bus: container[:bus],
        ).call(text)
        case proposal&.status
        when :deploy
          args = proposal.target.to_s
          args = "#{args} --confirm" if text.match?(/(?:^|\s)--confirm(?:\s|$)/i)
          return dispatch_slash("/deploy #{args}", container:, felt_sense:, on_turn:)
        when :ambiguous
          return Master::Result.ok({ rendered: proposal.message, output: proposal.message })
        when :unavailable
          return Master::Result.err(proposal.message, category: :infrastructure)
        when :unsupported
          return Master::Result.ok({ rendered: proposal.message, output: proposal.message })
        end
        if (shorthand = imperative_shorthand(text))
          return dispatch_slash(shorthand, container:, felt_sense:, on_turn:, cancellation:)
        end

        # bus: the media lane runs outside the pipeline stages; the stage:mov0
        # events it publishes are what move the spinner off "intake" and carry
        # the live download percentage.
        return Master::Io::MediaIntent.dispatch(text, root: container.fetch(:root, Dir.pwd), bus: container[:bus]) if Master::Io::MediaIntent.handles?(text)
        return casual_reply(text, container:, felt_sense:, on_chunk:, image:) if public_research_request?(text)
        # A question is for the agent, which has tools and this turn's evidence rule. Command
        # inference reads a question's words as an operator command: a council review of the
        # whole diff, or a shell lookup of "which file defines X".
        return casual_reply(text, container:, felt_sense:, on_chunk:, image:) if question?(text)

        intercepted = deterministic_intercept(text, container:)
        return intercepted if intercepted

        inferred = infer_operator_command(text, container:)
        return dispatch_inferred(inferred, container:, felt_sense:, on_turn:, cancellation:) if inferred
        return dispatch_reading(text, container:, felt_sense:, on_turn:, cancellation:) if full_workflow_intent?(text)
        return casual_reply(text, container:, felt_sense:, on_chunk:, image:) if casual?(text)

        run_fold(text, container:, on_turn:, cancellation:)
      end

      def visitor? = Fiber[:master_visitor] == true

      DOCUMENT_ARCHIVE_ACTION = /\A\s*(?:please\s+)?(?:analy[sz]e|transcribe|decipher|sequence|organize|sort|go through|go into|enter|open|read)\b|\b(?:tell|ask)\s+master\s+to\s+(?:analy[sz]e|transcribe|decipher|sequence|organize|sort|go through|go into|enter|open|read)\b/i.freeze
      DOCUMENT_ARCHIVE_SUBJECT = /\b(?:handwrit\w*|letters?|correspondence|postcards?|old notes?)\b/i.freeze

      def document_archive_request?(text)
        value = text.to_s.strip
        return false if value.empty? || question?(value)

        value.match?(DOCUMENT_ARCHIVE_ACTION) && value.match?(DOCUMENT_ARCHIVE_SUBJECT)
      end

      def document_archive_args(text)
        value = text.to_s
        match = value.match(/\b(?:in|from|under|inside)\s+(?:(?:the|my|our)\s+)?(?:folder\s+)?(?:"([^"]+)"|'([^']+)'|(~?\/[^\s,;]+)|([A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*))/i)
        path = match&.captures&.compact&.first
        path ||= value[/~?\/[A-Za-z0-9_.\/-]+/] if path.nil?
        Shellwords.escape(path.to_s.empty? ? "photos" : path)
      end

      # Bare words that are complete instructions, not conversation. "status?"
      # is /status asked as a question — question?() would otherwise read the
      # trailing mark and hand it to chat. The go-words mean continue the
      # work: the convergence loop a bare "fix" starts, which picks up the
      # last run's residual focus. Matched as the whole utterance with
      # trailing punctuation only, so a sentence that contains the words
      # ("keep going, I'll make coffee", "gone fishing") stays a sentence.
      # Below the visitor check, as every route to the registry is.
      def imperative_shorthand(text)
        value = text.to_s.strip
        return "/status" if value.match?(/\Astatus[?.!]?\z/i)
        return "/fix" if value.match?(/\A(?:go|go on|keep going|carry on|continue)[.!]?\z/i)

        nil
      end

      # Keep remote pairing possible without opening the rest of the command registry.
      def visitor_pair_redemption?(text)
        match = text.to_s.match(%r{\A/pair\s+(\S+)\s*\z}i)
        return false unless match && defined?(Master::Ground::Pairing)

        code = match[1]
        alphabet = Master::Ground::Pairing::ALPHABET
        code.length == Master::Ground::Pairing::CODE_BYTES &&
          code.upcase.each_char.all? { |character| alphabet.include?(character) }
      end

      # /fix writes code, so a line opening with "fix" is the command only when it names a file path or a
      # tree, is about code, or is the word alone; "fix the broken heater in my flat" is a person talking.
      FIX_TREES = /(?:lib|test|app|master|rails|openbsd|studio|itself|self|face)\b/i
      FIX_TARGET = %r{\s+(?:the\s+)?(?:\S*/\S*|\S+\.\w{1,5}\b|#{FIX_TREES})}i
      FIX_SUBJECT = /\b(?:bugs?|violations?|lint|tests?|specs?|errors?|failures?|code|build|checks?)\b/i
      FIX_COMMAND = /\A\s*fix(?:\s*[.!]?\s*\z|#{FIX_TARGET}|\b(?=.*#{FIX_SUBJECT}))/i

      # A sentence that is exactly a registry word, "status" or "help", runs that
      # command without a model's inference. Below the visitor check, as every route
      # to the registry is: a visitor typing "status" gets a conversation.
      def deterministic_intercept(text, container:)
        commands = container[:commands]
        word, args = text.sub(%r{\A/}, "").split(/\s+/, 2)
        return unless commands.respond_to?(:key?) && commands.key?(word.to_s.downcase)

        dispatch_slash("/#{word.downcase} #{args}".strip, container:)
      end

      def dispatch_reading(text, container:, felt_sense: nil, on_turn: nil, cancellation: nil)
        inferred = { command: "fix", args: reading_args(pass_args_from(text)), confidence: 0.9 }
        dispatch_inferred(inferred, container:, felt_sense:, on_turn:, cancellation:)
      end

      # One slash verb; the mode carries the intent. Legacy spellings stay as
      # thin rewrites so old prompts and scripts reach the same governed owner.
      PIPELINE_COMMANDS = %w[fix].freeze
      FIX_MODE_ALIASES = {
        "audit" => "audit", "review" => "audit", "critique" => "audit",
        "council" => "audit", "scan" => "repair",
        "visual" => "visual", "style" => "visual",
        "elevate" => "elevate", "map" => "elevate",
        "all" => "all", "workflow" => "all", "triad" => "all",
        "sweep" => "all", "through" => "all", "self" => "all"
      }.freeze
      MODEL_ALIASES = FIX_MODE_ALIASES.keys.freeze
      FIX_MODE_EXTRA_FLAGS = { "scan" => "--dry-run" }.freeze
      PIPELINE_WORDS = (PIPELINE_COMMANDS + MODEL_ALIASES).freeze
      FOLD_SLASH = %w[fold run].freeze
      READ_SLASH = %w[why laws].freeze
      CONVERGENCE_SLASH = { "prove" => "--prove", "explain" => "--explain" }.freeze
      FIX_PIN_SLASH = { "simplify" => "--simplify", "security" => "--security" }.freeze
      # Keep the literal list: the operator ratchet reads this one declaration
      # without evaluating Ruby, so a formatting refactor must not hide verbs.
      PIPELINE_SLASH = %w[fix audit review critique council scan visual style elevate map all self workflow triad sweep through prove explain simplify security].freeze

      INFER_MIN_CONFIDENCE = 0.62

      def infer_operator_command(text, container:)
        value = infer_command_value(text, container:)
        return unless value

        command = value.command.to_s
        conf = value.infer_confidence.to_f
        # Always accept through-class commands; other commands need confidence floor.
        return if !PIPELINE_WORDS.include?(command) && conf < INFER_MIN_CONFIDENCE

        mode = FIX_MODE_ALIASES[command]
        extra_flags = FIX_MODE_EXTRA_FLAGS[command]
        reading = mode.nil? && reading_intent?(command, text)
        command = normalize_inferred_command(command)
        return if READ_SLASH.include?(command)
        return unless answered?(command, container)

        { command:, args: inferred_args(command:, value:, text:, reading:, mode:, extra_flags:), confidence: conf }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "TurnRouter.infer_operator_command")
        nil
      end

      # patterns.yml infers words no handler takes, and a sentence that merely
      # named one died there: "read the dmesg module" answered "unknown command:
      # /dmesg". An inferred word becomes a command only when the registry answers
      # it; every pipeline word rewrites to /fix (rewrite_slash).
      def answered?(command, container)
        commands = container[:commands]
        resolved = Stages::Route::SPELLINGS.fetch(command, command)
        PIPELINE_WORDS.include?(command) || !commands.respond_to?(:key?) || commands.key?(resolved)
      end

      def infer_command_value(text, container:)
        ctx = PipelineContext.build(user_message: text, intent: :llm, message: text)
        inferred = Stages::Infer.new(bus: container[:bus], session: container[:session]).call(ctx)
        return unless inferred.ok?

        value = inferred.value!
        value.intent == :command ? value : nil
      end

      # Every legacy pipeline spelling is normalized to the one /fix dispatcher.
      def normalize_inferred_command(command)
        return "fix" if PIPELINE_WORDS.include?(command)

        command
      end

      # Preview remains an explicit read; legacy mode aliases already carry a preset.
      def reading_intent?(command, text)
        return false if FIX_MODE_ALIASES.key?(command)

        text.match?(/--dry-run|--no-autofix|\bpreview\b/i)
      end

      # Every /fix spelling takes the same target. A legacy mode word is retained
      # as an explicit --mode flag before the shared dispatcher sees the request.
      def inferred_args(command:, value:, text:, reading:, mode: nil, extra_flags: nil)
        args = PIPELINE_SLASH.include?(command) ? pass_command_args(value, text) : value.args.to_s
        args = ["--mode=#{mode}", extra_flags, args].compact.reject(&:empty?).join(" ") if mode
        reading ? reading_args(args) : args
      end

      def pass_command_args(value, text)
        args = value.args.to_s
        refined = pass_args_from(text)
        # Prefer a narrower tree path when Infer only captured a coarse alias.
        args = refined if !refined.empty? && (args.empty? || refined.start_with?("#{args}/") || refined != args && refined.include?("/"))
        args = refined if args.empty?
        args = "master" if args.match?(/\A(?:itself|self)\z/i) && text.match?(/\bmaster\b/i)
        args = "master" if args.match?(/\Aitself\z/i)
        args
      end

      def reading_args(args) = [READING_FLAGS, args.to_s.strip].reject(&:empty?).join(" ")

      def full_workflow_intent?(text)
        route = CLI::IntentRouter.new.route(text)
        route[:intent] == :run_full_workflow ||
          text.match?(/\b(?:through\s+(?:master|itself|rails)|singularity|self[-\s]?apply|run\s+(?:master|rails)\s+through)\b/i)
      end

      def pass_args_from(text)
        if (m = text.match(%r{\brails(?:[:/]([\w./-]+))?}i))
          return m[1] ? "rails/#{m[1]}" : "rails"
        end
        if (m = text.match(%r{\bthrough\s+rails(?:[:/]([\w./-]+))?}i))
          return m[1] ? "rails/#{m[1]}" : "rails"
        end
        if text.match?(/\b(?:itself|self)\b/i) && !text.match?(/\brails\b/i)
          return text.match?(/\blib\b/i) ? "self" : "master"
        end
        return "master" if text.match?(/\bmaster\b/i) && !text.match?(/\brails\b/i)
        return "face" if text.match?(/\bface\b|\bweb\s*ui\b/i)

        ""
      end

      def dispatch_inferred(inferred, container:, felt_sense: nil, on_turn: nil, cancellation: nil)
        command = inferred[:command].to_s
        args = inferred[:args].to_s
        container[:bus]&.publish("infer:auto", command:, args:, confidence: inferred[:confidence])
        slash = args.empty? ? "/#{command}" : "/#{command} #{args}"
        dispatch_slash(rewrite_slash(slash), container:, felt_sense:, on_turn:, cancellation:)
      end

      # Core::Fold's constitution requires exec evidence (test_pass, scan_clean,
      # ...) before it admits a `done` effect — right for a coding goal, but
      # it means the Fold can never answer "hi" alone. Plain conversation (no
      # recognized coding-task keyword, no risk-pattern hit) skips the Fold
      # entirely and talks straight to the agent, which already carries the
      # persona system prompt, model routing, and visitor-scoped tools
      # (AskLlm/WebSearch — see Fiber[:master_visitor] in tool_registry.rb).
      # Public-site reading belongs to the tool-capable chat agent, not the
      # coding Fold. A news request must reach Browser/WebBrowse instead of
      # proposing an HTTP effect under the plan profile, which has no network.
      PUBLIC_RESEARCH_ACTION = /\b(?:go to|open|visit|browse|crawl|read|fetch|check|look at|search|summari[sz]e|give me|tell me|latest|current|today(?:['\u2019]s)?|headlines?|news)\b/i.freeze
      PUBLIC_SITE = %r{(?:\bhttps?://|\bwww\.)[a-z0-9.-]+\.[a-z]{2,}}i.freeze
      PUBLIC_RESEARCH_MUTATION = /\b(?:commit|deploy|delete|edit|modify|update|change|purchase|buy|pay|book|send|post|publish|submit|comment)\b/i.freeze

      def public_research_request?(text)
        value = text.to_s.strip
        return false if value.empty? || value.match?(PUBLIC_RESEARCH_MUTATION)

        value.match?(PUBLIC_SITE) && value.match?(PUBLIC_RESEARCH_ACTION)
      end

      QUESTION_START = /\A(?:please\s+)?(?:in\s+(?:one|a\s+few)\s+(?:sentence|word)s?,?\s+)?(?:what|why|how|which|where|when|who|whom|whose|does|do|did|is|are|was|were|can|could|should|would|will)\b/i.freeze
      QUESTION_IMPERATIVE = /\A(?:please\s+)?(?:do|can|will)\s+(?:fix|refactor|add|implement|make|create|build|update|change|remove|delete|write|generate)\b/i.freeze

      def question?(text)
        value = text.to_s.strip
        return true if value.end_with?("?")
        return false if value.match?(QUESTION_IMPERATIVE)

        value.match?(QUESTION_START)
      end

      def casual?(text)
        return false if text.match?(FoldRisk::HIGH_PATTERNS) || text.match?(FoldRisk::MEDIUM_PATTERNS)

        CLI::IntentRouter.new.classify(text) == :unknown
      end

      def casual_reply(text, container:, felt_sense: nil, on_chunk: nil, image: nil)
        agent = container[:agent]
        return Master::Result.err("agent unavailable", category: :infrastructure) unless agent
        return Master::Result.err(Master.no_api_key_message, category: :no_api_key) unless Master.llm_reachable?((agent.model if agent.respond_to?(:model)))

        result = agent.call({ message: text, on_chunk:, felt_sense:, task_type: "chat", image: })
        return result if result.is_a?(Master::Result::Err)

        reply = result.value!.to_s
        Master::Result.ok({ output: reply, rendered: reply })
      rescue StandardError => e
        Master::Result.err("chat: #{e.message}", category: :infrastructure)
      end

      def run_fold(goal, container:, on_turn: nil, cancellation: nil)
        goal = goal.to_s.strip
        # Defence in depth: TurnRouter.call already routes visitors to
        # casual_reply, but run_fold is also reachable via dispatch_slash when
        # Intake classifies input as :llm. The Fold can exec; visitors cannot.
        return Master::Result.err("fold: not available to visitors", category: :policy) if visitor?
        cancellation.activate! if cancellation&.respond_to?(:activate!)
        unless Master.llm_reachable?(container[:agent]&.model)
          return Master::Result.err(Master.no_api_key_message, category: :no_api_key)
        end

        Master::Trace::Dmesg.under("fold0") do
          root, risk, mode = assess_fold_risk(goal, container:)
          memory = prepare_fold_memory(goal:, container:, risk:)
          fold_to_result(run_fold_pipeline(goal, root:, container:, on_turn:, memory:, risk:, mode:, cancellation:))
        end
      rescue StandardError => e
        Master::Result.err("fold0: #{e.message}", category: :infrastructure)
      end

      def assess_fold_risk(goal, container:)
        root = container.fetch(:root, Dir.pwd)
        assessment = Master::Operator::Mode.assess(goal, root:)
        container[:bus]&.publish(
          "fold:risk",
          risk: assessment[:risk],
          intent: assessment[:intent],
          mode: assessment[:mode],
          model_tier: assessment[:model_tier],
          council_required: assessment[:council_required],
        )
        [root, assessment[:risk], assessment[:mode]]
      end

      def run_fold_pipeline(goal, root:, container:, on_turn:, memory:, risk:, mode:, cancellation: nil)
        CoreBridge.run(
          goal,
          root:,
          bus: container[:bus],
          model_id: container[:agent]&.model,
          on_turn:,
          memory:,
          container:,
          risk:,
          mode:,
          cancellation:,
        )
      end

      def prepare_fold_memory(goal:, container:, risk:)
        memory = Master::Core::Memory.new(risk:)
        memory.note(:risk, risk)
        ideation = DeliberationPrep.prepare!(goal:, container:, risk:)
        if ideation
          DeliberationPrep.seed_memory!(memory, ideation)
        elsif FoldRisk.ideation_required?(risk)
          memory.note(:chosen, "proceed: ideation skipped (no agent)")
          memory.proof.mark_ideation_complete!
        end
        memory
      end

      # Retained for direct callers that explicitly request the old narrow read.
      READING_FLAGS = "--dry-run --critique --only critique,map"

      def rewrite_slash(input)
        name, rest = input.sub(%r{\A/}, "").split(/\s+/, 2)
        name = name.to_s.downcase
        return input unless PIPELINE_SLASH.include?(name)

        rewritten_pipeline(name, rest.to_s.strip)
      end

      def rewritten_pipeline(name, rest)
        if (mode = FIX_MODE_ALIASES[name])
          return ["/fix", "--mode=#{mode}", FIX_MODE_EXTRA_FLAGS[name], rest].compact.reject(&:empty?).join(" ")
        end
        return ["/fix", rest].reject(&:empty?).join(" ") if name == "fix"

        ["/fix", pinned_flag(name), rest].compact.reject(&:empty?).join(" ")
      end

      def pinned_flag(name)
        CONVERGENCE_SLASH[name] || FIX_PIN_SLASH[name]
      end

      def dispatch_slash(input, container:, felt_sense: nil, on_turn: nil, cancellation: nil)
        name, rest = input.sub(%r{\A/}, "").split(/\s+/, 2)
        return run_fold(rest.to_s, container:, on_turn:, cancellation:) if FOLD_SLASH.include?(name.to_s.downcase)

        ctx = PipelineContext.wrap(user_message: input, felt_sense:)
        ctx = unwrap(Stages::Intake.new(root: container.fetch(:root, Master::ROOT)).call(ctx))
        return ctx if ctx.is_a?(Master::Result)
        ctx = ctx.merge(cancellation:) if cancellation && ctx.respond_to?(:merge)

        if ctx.intent == :llm
          goal = ctx.message.to_s.strip
          goal = input.to_s.strip if goal.empty?
          return run_fold(goal, container:, on_turn:, cancellation:)
        end

        commands = container[:commands]
        return Master::Result.err("command: registry unavailable", category: :infrastructure) unless commands

        run_command_pipeline(ctx, container:, commands:)
      # ScriptError too: the outer rescue is the last one a re-raised
      # SyntaxError from a pipeline thread can meet, and StandardError-only
      # let it abort the whole session.
      rescue StandardError, ScriptError => e
        Master::Result.err("command: #{e.message}", category: :infrastructure)
      end

      def run_command_pipeline(ctx, container:, commands:)
        agent = container[:agent]
        bus = container[:bus]
        renderer = container[:renderer]
        ctx = unwrap(Stages::Route.new(commands:, agent:, bus:).call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        ctx = unwrap(Stages::DestructiveReview.new(deliberation: container[:deliberation], event_bus: bus).call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        ctx = unwrap(Stages::Execute.new(event_bus: bus).call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        Stages::Render.new(
          renderer:,
          output_check: container[:output_check],
          output_guard: container[:output_guard],
          event_bus: bus,
        ).call(ctx)
      end

      def fold_to_result(fold)
        text = fold_output_text(fold)
        value = { output: text, rendered: text, core: fold }
        return Master::Result.ok(value) if fold[:reason] == :complete

        category = {
          cancelled: :cancelled,
          trace_failed: :unknown_outcome,
          unknown_outcome: :unknown_outcome,
          recovery_failed: :recovery_failed,
          needs_user: :human_decision,
        }.fetch(fold[:reason], :policy)
        Master::Result.err(text, category:)
      end

      def fold_output_text(fold)
        header = "fold0: #{fold[:reason]}, #{fold[:turns]} turns"
        header += ", risk #{fold[:risk]}" if fold[:risk]
        turns = Array(fold[:transcript]).map { |entry| Master::CLI::CoreBridge.report_turn(entry) }
        [header, *turns, fold[:summary]].compact.join("\n")
      end

      def unwrap(result)
        return result unless result.ok?

        result.value!
      end
    end
  end
end
