# frozen_string_literal: true

require "optparse"
require_relative "../trace/dmesg"
require_relative "../trace/event_bus"
require_relative "../trace/effect_observer"

module Master
  module CLI
    # `bin/master core`: the fold spine only. The rest of bin/master boots the full
    # runtime (soul, scan, voice); this drives lib/core.rb with a scripted model
    # unless --real. A missing goal exits 64 with the usage.
    module CoreCommand
      USAGE = "usage: bin/master core [--root PATH] [--max-turns N] [--real [--model ID] GOAL | --offline-inspect | --offline-check PATH]"
      REAL = "drive a live LLM (needs a provider key); default is the scripted constitution check"

      # Two successful but unrecognised commands, then a deliberately refused done.
      class NullModel
        def initialize(goal)
          @goal = goal

          @script = [
            Master::Core::Effect.exec(["true"]),
            Master::Core::Effect.exec(["true"]),
            Master::Core::Effect.done("noop complete: #{@goal}"),
          ]
        end

        def turns = @script.size

        def propose(_context, verbs:, **)
          unsupported = @script.map(&:verb).uniq - verbs
          raise "kernel verbs unavailable: #{unsupported.join(", ")}" unless unsupported.empty?

          @script.shift || Master::Core::Effect.done("noop complete: #{@goal}")
        end
      end

      module_function

      def parser(options)
        OptionParser.new do |opts|
          opts.banner = USAGE
          opts.on("--root PATH") { |path| options[:root] = path }
          opts.on("--max-turns N", Integer) { |n| options[:max_turns] = n }
          opts.on("--real", REAL) { options[:real] = true }
          opts.on("--model ID") { |id| options[:model] = id }
          opts.on("--offline-check PATH", "check a Ruby file without an LLM") { |path| options[:offline_check] = path }
          opts.on("--offline-inspect", "inspect Git status and HEAD without an LLM") { options[:offline_inspect] = true }
        end
      end

      def run(argv, master_root: Master::ROOT)
        options = { root: Dir.pwd, max_turns: 40, real: false, model: nil }
        opts = parser(options)
        opts.parse!(argv)
        goal = argv.join(" ").strip
        if offline?(options)
          if options[:real] || options[:model] || !goal.empty? || (options[:offline_inspect] && options[:offline_check])
            Master::Trace::Dmesg::Report.print("/help", "offline inspection does not accept a model or arbitrary goal", io: $stderr)
            return 64
          end
          goal = options[:offline_check] ? "check Ruby syntax" : "inspect repository"
        end

        if goal.empty?
          Master::Trace::Dmesg::Report.print("/help", opts.to_s, io: $stderr)
          return 64
        end

        fold(goal, options, master_root:)
      end

      def fold(goal, options, master_root:)
        root = File.expand_path(options.fetch(:root))
        memory = Master::Core::Memory.new
        model = model_for(goal, options, memory:)
        refusals = []
        probe_policy = Master::CLI::CoreBridge.read_only_probe(root:)
        capabilities = offline?(options) ? Master::Core::Capabilities.read_only : Master::Core::Capabilities.for(:fix)

        result = Master::CLI::CoreBridge.build_fold(
          root:, data_dir: File.join(master_root, "data"), model:, capabilities:,
          world: Master::CLI::CoreBridge.build_world(
            root:, container: nil, capabilities:, probe: probe_policy,
          ),
          memory:, max_turns: turn_budget(model, options),
          observer: refusal_recorder(refusals, display: offline?(options)),
          effect_observer: Master::Trace::EffectObserver.new(bus: event_bus(root)),
          probe: probe_policy,
        ).run(goal)
        verdict(result, refusals, real: options[:real] || offline?(options))
      end

      # Each refused `done` leaves its reason, which the verdict reads.
      def refusal_recorder(refusals, display: false)
        lambda do |turn:, effect:, observation:|
          refusals << observation.detail if effect.done? && !observation.ok?
          Master::Trace::Dmesg.status("core0", observation.message) if display && %i[read probe].include?(effect.verb)
        end
      end

      # The scripted run ends when its script does; a real model gets --max-turns.
      def turn_budget(model, options)
        return options.fetch(:max_turns) if options[:real]
        return [model.turns, options.fetch(:max_turns)].min if offline?(options)

        model.turns
      end

      def offline?(options) = !!(options[:offline_inspect] || options[:offline_check])

      def model_for(goal, options, memory: nil)
        if offline?(options)
          memory ||= Master::Core::Memory.new
          commands = options[:offline_check] ? [["ruby", "-c", options[:offline_check]]] : [%w[git status --short], %w[git log -1 --oneline]]
          effects = commands.map { |argv| Master::Core::Effect.probe(argv) }
          memory.procedural.register_effect_recipe("inspect_repository", effects)
          return memory.procedural.replay("inspect_repository")
        end
        return NullModel.new(goal) unless options[:real]

        Master::Core::Model.new(**{ model_id: options[:model] }.compact)
      end

      # A run against the checkout itself records into MASTER's own event log.
      def event_bus(root)
        own = [Master::ROOT, Master::REPO_ROOT].map { |path| File.expand_path(path) }.include?(root)
        Master::Trace::EventBus.new(event_log: Master::Trace::Log::Event.new(root: own ? Master::ROOT : root))
      end

      # The scripted run is a check of the constitution, not a completed goal. It
      # execs true(1) twice, then declares done. Neither command is a registered
      # test or clean-scan producer, so World issues no proof receipt: exit 0 says
      # the Fold refused a false completion claim,
      # and exit 1 says it admitted done on self-graded evidence. With --real, exit
      # 0 means the model's goal completed.
      def verdict(result, refusals, real:)
        reason = result.reason

        if real
          Master::Trace::Dmesg.attach("core0", "master0", "#{reason}, #{result.turns} turns")
          Master::Trace::Dmesg.status("core0", result.summary)
          return reason == :complete ? 0 : 1
        end

        if reason != :complete && refusals.any? { |detail| detail.include?("evidence_for_done") }
          Master::Trace::Dmesg.attach("core0", "master0", "held, done refused without passing evidence")
          Master::Trace::Dmesg.status("core0", refusals.last)
          return 0
        end

        Master::Trace::Dmesg.status("core0", "#{reason}, scripted done was not refused for evidence: #{result.summary}")
        1
      end
    end
  end
end
