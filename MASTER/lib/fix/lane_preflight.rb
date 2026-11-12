# frozen_string_literal: true

require_relative "../io/lane_state"
require_relative "lane_probe"

module Master
  module Fix
    # Before /fix reads anything, print the model each kind of call will get
    # and refuse to start on a free or local one while a better lane is live:
    # on 2026-10-26 three runs read the tree on gemma3:4b because the router
    # excluded an idle opus. MASTER_FIX_FREE_OK=1 accepts the free lane.
    #
    # The symmetric case is no lane at all. On 2026-11-12 an audit run entered
    # pass 0 with every catalogue lane dead, spent or unreachable and paid 25
    # failed model calls to rediscover that one call at a time, each web-chat
    # refusal arriving after 17 to 163s. One bounded probe before the run
    # answers the question once; a run with nothing to answer it is refused
    # before its first pass. MASTER_FIX_PROBE=0 skips the probe.
    module LanePreflight

      OPERATIONS = %i[tree structural_review file_write code_generation].freeze

      Row = Data.define(:operation, :model, :kind)

      # The pass runner probes too; the preflight probe covers the run, so the
      # pass runner skips its own when this one ran. Process-scoped on purpose:
      # one /fix run per process.
      class << self
        def probed? = @probed == true

        def mark_probed!
          @probed = true
        end
      end

      module_function

      # nil when the run may start, else a Result::Err naming the operation,
      # the model it would get, and the lane it should have had.
      def check(agent:, env: ENV)
        return unless agent.class.method_defined?(:model_for)

        rows = routes(agent)
        explain_skipped
        weak = rows.find { |row| free_class?(row.model) }
        better = Master::Io::LaneSelection.live_lanes.find { |id| !free_class?(id) }
        if weak && better && env["MASTER_FIX_FREE_OK"] != "1"
          mark_probed!
          return refuse(weak, better)
        end

        probe_refusal(agent)
      end

      def routes(agent)
        OPERATIONS.map do |operation|
          model = agent.model_for(operation:).to_s
          Row.new(operation:, model:, kind: Master::Io::LaneSelection.kind(model))
        end.each { |row| say("#{row.operation} -> #{row.model} (#{row.kind})") }
      ensure
        Fiber[:master_operation] = nil
      end

      # One line per catalogue lane LaneState refuses, with the store and its
      # reason, so a run says which lanes it is not using and why.
      def explain_skipped
        lanes = Master::Io::LaneSelection.catalogue.uniq { |id| Master::Io::LaneState.lane_of(id) }
        lanes.map { |id| Master::Io::LaneState.verdict(id) }.reject(&:usable?).each do |verdict|
          say("skipped #{verdict.model}: #{verdict.source}, #{verdict.reason}")
        end
      end

      def refuse(weak, better)
        message = "fix: #{weak.operation} would run on #{weak.model} (#{weak.kind}) while #{better} is live; " \
                  "the router is excluding it. MASTER_FIX_FREE_OK=1 runs anyway"
        say(message)
        Master::Result.err(message, category: :human_decision)
      end

      # nil when at least one probed lane answered, else one line refusing the
      # run. A catalogue with nothing left alive needs no calls; anything else
      # gets the same bounded probe the pass runner runs, before the run can
      # spend its budget on a dead catalogue.
      def probe_refusal(agent)
        return if probed? || !LaneProbe.enabled?
        return unless agent.class.method_defined?(:ask_once)

        mark_probed!
        models = probed_models(agent)
        return refuse_dead_catalogue if models.empty?

        rows = LaneProbe.run(models:, ask: LaneProbe.ask_with(agent))
        return if rows.any? { |row| row.status == :ok }

        refuse_no_lane
      end

      def probed_models(agent)
        models = if agent.respond_to?(:candidate_models)
                   Array(agent.candidate_models(task_type: :code_generation))
                 else
                   Master::Io::LaneSelection.catalogue
                 end
        models.select { |model| Master::Io::LaneSelection.alive?(model) }
      end

      # Selection already holds a verdict on every lane (quota records, the
      # hand list); the skipped lines above name each one. No probe can help.
      def refuse_dead_catalogue
        message = "fix: every catalogue lane is marked dead or spent; the model phase has nothing to run on"
        say(message)
        Master::Result.err("#{message}. Revive a lane or set MASTER_FIX_PROBE=0 to run without one",
                           category: :offline)
      end

      def refuse_no_lane
        message = "fix: no model lane answered the preflight probe; the model phase has nothing to run on"
        say(message)
        Master::Result.err("#{message}. Start a lane or set MASTER_FIX_PROBE=0 to run without one",
                           category: :offline)
      end

      def free_class?(model)
        Master::Io::LaneSelection::FREE_CLASS_KINDS.include?(Master::Io::LaneSelection.kind(model))
      end

      def say(text) = Master::Trace::Dmesg.status("lane0", text)
    end
  end
end
