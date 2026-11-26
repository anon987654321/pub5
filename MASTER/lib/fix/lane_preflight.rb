# frozen_string_literal: true

require_relative "../io/lane_state"

module Master
  module Fix
    # Admission checks operation routing and the explicit free-lane policy only.
    # Live provider probes run after deterministic fast fixes in PassRunner, so
    # an unavailable model cannot suppress work that does not need one.
    # Consensus remains a candidate-level interlock for high-risk mutations.
    module LanePreflight

      OPERATIONS = %i[tree structural_review file_write code_generation].freeze

      Row = Data.define(:operation, :model, :kind)

      module_function

      # A lexical read with all model phases disabled needs no provider admission.
      # A repair or explicitly requested critique still uses the ordinary gate.
      def deterministic_observation?(mode:, writes_requested:, critique:, only:, env: ENV)
        mode == "repair" && !writes_requested && critique != true &&
          (only.nil? || only.to_s == "fix") && env["MASTER_SCAN_DETERMINISTIC"] == "1" &&
          %w[MASTER_FIX_TREE MASTER_FIX_DEEP_TRACE MASTER_FIX_STRUCTURAL_REVIEW MASTER_FIX_PREVIEW]
            .all? { |key| env[key] == "0" }
      end

      # nil when the run may start, else a Result::Err naming the operation,
      # the model it would get, and the lane it should have had.
      def check(agent:, env: ENV)
        return unless agent.class.method_defined?(:model_for)

        rows = routes(agent, env:)
        explain_skipped(env:)
        return if env["MASTER_FIX_FREE_OK"] == "1"

        conflict = free_conflict(agent, rows)
        return refuse(*conflict) if conflict

        # The operator must explicitly accept a run whose every operation is
        # routed to a free-class lane. Live availability is measured later.
        refuse_free_only(rows) if rows.all? { |row| free_class?(row.model) }
      end

      # The first free-class operation a better lane could replace, with that
      # lane; nil when every free-class row has no better alternative.
      def free_conflict(agent, rows)
        rows.each do |row|
          next unless free_class?(row.model)

          better = better_model(agent, row.operation)
          return [row, better] if better
        end
        nil
      end

      def routes(agent, env: ENV)
        rows = OPERATIONS.map do |operation|
          model = agent.model_for(operation:).to_s
          Row.new(operation:, model:, kind: Master::Io::LaneSelection.kind(model))
        end
        if env["MASTER_FIX_ROUTE_DIAGNOSTICS"] == "1" && Master::Trace::Dmesg.verbose?
          rows.each { |row| say("#{row.operation} -> #{row.model} (#{row.kind})") }
        end
        rows
      ensure
        Fiber[:master_operation] = nil
      end

      # The pool census is deliberately opt-in: most runs need the chosen route,
      # not a line for every provider that has no quota, key or live process.
      def explain_skipped(env: ENV)
        return unless env["MASTER_FIX_POOL_DIAGNOSTICS"] == "1" && Master::Trace::Dmesg.verbose?

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

      # A run whose every operation lands on a free-class lane has no paid,
      # subscription or gateway lane to answer: it would crawl the whole tree at
      # free pace, where a whole-tree /fix read about two files a minute and the
      # 2,630-file tree was a day long. Refused before the run spends its budget,
      # so a keyless fleet is a refusal the operator sees, never a silent stall.
      # MASTER_FIX_FREE_OK=1 is the deliberate opt-in to free pace.
      def refuse_free_only(rows)
        lanes = rows.map(&:model).uniq.join(", ")
        message = "fix: every operation would run on a free-class lane (#{lanes}); no paid, subscription or " \
                  "gateway lane is live. A free-only fleet crawls the whole tree, so it is refused before it " \
                  "starts. Set MASTER_MODEL to a live paid lane, or MASTER_FIX_FREE_OK=1 to accept free pace; " \
                  "no files were changed."
        say(message)
        Master::Result.err(message, category: :human_decision)
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
