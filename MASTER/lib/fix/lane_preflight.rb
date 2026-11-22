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

      # nil when the run may start, else a Result::Err naming the operation,
      # the model it would get, and the lane it should have had.
      def check(agent:, env: ENV)
        return unless agent.class.method_defined?(:model_for)

        rows = routes(agent)
        explain_skipped
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
