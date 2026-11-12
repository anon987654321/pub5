# frozen_string_literal: true

require_relative "../io/lane_state"
require_relative "lane_probe"

module Master
  module Fix
    # Before /fix reads anything, print the model each kind of call will get
    # and refuse to start on a free or local one while a better lane is live.
    # The bounded readiness pass reserves capacity for keyless providers,
    # stops at the first real reply and refuses before touching the tree if
    # every eligible provider fails. Provider-by-provider diagnostics are verbose.
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
        conflict = nil
        rows.each do |row|
          next unless free_class?(row.model)

          better = better_model(agent, row.operation)
          next unless better

          conflict = [row, better]
          break
        end
        if conflict && env["MASTER_FIX_FREE_OK"] != "1"
          mark_probed!
          return refuse(*conflict)
        end

        probe_refusal(agent)
      end

      def routes(agent)
        OPERATIONS.map do |operation|
          model = agent.model_for(operation:).to_s
          Row.new(operation:, model:, kind: Master::Io::LaneSelection.kind(model))
        end.each { |row| say("#{row.operation} -> #{row.model} (#{row.kind})") if Master::Trace::Dmesg.verbose? }
      ensure
        Fiber[:master_operation] = nil
      end

      # One line per catalogue lane LaneState refuses, with the store and its
      # reason, so a run says which lanes it is not using and why.
      def explain_skipped
        return unless Master::Trace::Dmesg.verbose?

        lanes = Master::Io::LaneSelection.catalogue.uniq { |id| Master::Io::LaneState.lane_of(id) }
        lanes.map { |id| Master::Io::LaneState.verdict(id) }.reject(&:usable?).each do |verdict|
          say("skipped #{verdict.model}: #{verdict.source}, #{verdict.reason}")
        end
      end

      def refuse(weak, better)
        message = "fix: #{weak.operation} would run on #{weak.model} (#{weak.kind}) while #{better} is live; " \
                  "routing disagrees with provider availability. Inspect /model list; no files were changed."
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

        rows = LaneProbe.run(models:, ask: LaneProbe.ask_with(agent), stop_on_success: true)
        return if rows.any? { |row| row.status == :ok }

        refuse_no_lane(rows)
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
        message = "fix: no eligible model provider is available; all discovered lanes are unavailable or over quota"
        Master::Result.err("#{message}. Inspect /doctor keyless or /model list; no files were changed.",
                           category: :offline)
      end

      def refuse_no_lane(rows)
        message = "fix: no model provider answered after #{rows.size} readiness checks"
        Master::Result.err("#{message}. Inspect /doctor keyless or /model list; no files were changed.",
                           category: :offline)
      end

      # Agent#candidate_models is the router's complete, reachable fallback
      # chain for this operation. The global inventory can contain a live model
      # that this operation is not allowed to use, so it is only a compatibility
      # fallback for small diagnostic agents without that interface.
      def better_model(agent, operation)
        candidates = if agent.respond_to?(:candidate_models)
                       agent.candidate_models(task_type: operation)
                     else
                       Master::Io::LaneSelection.live_lanes
                     end
        Master::Io::LaneSelection.order(Array(candidates)).find { |id| !free_class?(id) }
      end

      def free_class?(model)
        Master::Io::LaneSelection::FREE_CLASS_KINDS.include?(Master::Io::LaneSelection.kind(model))
      end

      def say(text) = Master::Trace::Dmesg.status("lane0", text)
    end
  end
end
