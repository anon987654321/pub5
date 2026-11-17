# frozen_string_literal: true

require "set"

module Master
  module Fix
    # Evidence-bounded route selection for the existing /fix backlog scheduler.
    # This class chooses work; Kernel, TaskContract, Transaction and the normal
    # proof/commit pipeline remain the only execution authority.
    class AdaptiveJourney
      TERMINAL_STATES = %w[PASS FAIL INCONCLUSIVE BLOCKED TIMEOUT DELIVERY_FAILED].freeze
      LEARNABLE_STATES = %w[PASS FAIL].freeze
      DEFAULT_EXPLORATION = 0.12
      MAX_HISTORY = 500

      Route = Data.define(
        :id, :actions, :evidence_ids, :impact, :confidence, :priority, :cost,
        :risk, :reversibility, :causes, :preserves, :dependencies
      )
      Decision = Data.define(:route, :score, :reason, :alternatives, :exploration)

      attr_reader :history, :exploration_rate

      # history is supplied only from receipts that their owning ledger has
      # already validated. Unauthenticated claims never enter this projection.
      def initialize(history: [], exploration_rate: DEFAULT_EXPLORATION)
        @history = normalize_history(history).last(MAX_HISTORY).freeze
        @exploration_rate = Float(exploration_rate).clamp(0.0, 0.5)
        freeze
      end

      # Routes need grounded evidence, bounded estimates and satisfied explicit
      # prerequisites. A dependency that is another candidate is selected first;
      # a missing dependency blocks the route instead of being silently ignored.
      def choose(routes:, verified_evidence:, objective:, satisfied_dependencies: [], exploration: true)
        evidence = normalize_evidence(verified_evidence)
        candidates = Array(routes).filter_map { |row| normalize_route(row, evidence) }
        candidates = candidates.uniq(&:id)
        raise ArgumentError, "no route has grounded evidence and valid constraints" if candidates.empty?

        satisfied = clean_list(satisfied_dependencies, 500).to_set
        highest_priority = candidates.map(&:priority).max
        mission_band = candidates.select { |route| route.priority >= highest_priority - @exploration_rate }
        ready = mission_band.select do |route|
          route.dependencies.all? { |dependency| satisfied.include?(dependency) }
        end
        if ready.empty?
          pending = mission_band.flat_map(&:dependencies).uniq - satisfied.to_a
          raise ArgumentError, "highest-priority routes are blocked by unsatisfied dependencies: #{pending.sort.join(", ")}"
        end

        ranked = ready.map { |route| [route, route_score(route, objective:), route_explanation(route)] }
          .sort_by { |route, score, _| [-score, -route.priority, route.id] }
        selected = ranked.first

        # Exploration is local to the winning mission-priority band. A cheap,
        # unrelated task cannot displace a mission-critical prerequisite merely
        # because it has not been tried before.
        if exploration && ranked.size > 1 && underexplored?(ranked.first[0])
          alternative = ranked.drop(1).find do |route, score, _|
            underexplored?(route) &&
              route.priority >= ranked.first[0].priority - @exploration_rate &&
              score >= ranked.first[1] * (1.0 - @exploration_rate)
          end
          selected = alternative if alternative
        end

        route, score, reason = selected
        Decision.new(
          route:, score: score.round(4), reason:,
          alternatives: ranked.reject { |row| row[0].id == route.id }.first(5).map do |candidate, value, why|
            { id: candidate.id, score: value.round(4), priority: candidate.priority, reason: why }.freeze
          end.freeze,
          exploration: route.id != ranked.first[0].id
        )
      end

      # Causal edges are explicit trace assertions, never inferred from timing.
      # Dangling and self-referential edges are discarded.
      def causal_graph(events)
        nodes = {}
        edges = []
        Array(events).each do |event|
          row = event.to_h.transform_keys(&:to_s)
          id = row["id"].to_s
          next if id.empty?

          nodes[id] = {
            "id" => id, "kind" => row["kind"].to_s,
            "status" => row["status"].to_s, "evidence_id" => row["evidence_id"].to_s,
          }.freeze
          Array(row["caused_by"]).each do |parent|
            source = parent.to_s
            edges << [source, id].freeze unless source.empty? || source == id
          end
        end
        valid_edges = edges.uniq.select { |from, to| nodes.key?(from) && nodes.key?(to) }
        {
          "nodes" => nodes.sort.to_h.freeze,
          "edges" => valid_edges.freeze,
          "roots" => (nodes.keys - valid_edges.map(&:last)).sort.freeze,
        }.freeze
      end

      private

      def normalize_history(rows)
        Array(rows).filter_map do |raw|
          next unless raw.is_a?(Hash)

          row = raw.transform_keys(&:to_s)
          id = row["route_id"].to_s.strip
          state = row["status"].to_s.upcase
          evidence = row["evidence_id"].to_s
          next if id.empty? || !LEARNABLE_STATES.include?(state)
          next unless evidence.match?(/\A[0-9a-f]{64}\z/i)

          {
            "route_id" => id, "status" => state,
            "evidence_id" => evidence.downcase,
            "verified" => true,
            "reinforcement" => state == "PASS" ? 1.0 : -1.0,
          }.freeze
        end
      end

      def normalize_evidence(rows)
        Array(rows).each_with_object({}) do |raw, result|
          next unless raw.is_a?(Hash)

          row = raw.transform_keys(&:to_s)
          id = row["id"].to_s.strip
          digest = row["sha256"].to_s
          next if id.empty? || row["verified"] != true
          next unless digest.match?(/\A[0-9a-f]{64}\z/i)

          result[id] = row.freeze
        end.freeze
      end

      def normalize_route(raw, evidence)
        return unless raw.is_a?(Hash)

        row = raw.transform_keys(&:to_s)
        id = row["id"].to_s.strip
        actions = clean_list(row["actions"], 12)
        evidence_ids = clean_list(row["evidence_ids"], 12).select { |key| evidence.key?(key) }
        return if id.empty? || actions.empty? || evidence_ids.empty?

        impact = bounded_number(row["impact"], 0.0, 1.0)
        confidence = bounded_number(row["confidence"], 0.0, 1.0)
        priority = bounded_number(row.fetch("priority", 0.5), 0.0, 1.0)
        cost = bounded_number(row["cost"], 0.01, 100.0)
        risk = bounded_number(row["risk"], 0.0, 1.0)
        return unless %w[easy moderate hard].include?(row["reversibility"].to_s)

        Route.new(
          id:, actions: actions.freeze, evidence_ids: evidence_ids.freeze,
          impact:, confidence:, priority:, cost:, risk:,
          reversibility: row["reversibility"].to_s,
          causes: clean_list(row["causes"], 12).freeze,
          preserves: clean_list(row["preserves"], 12).freeze,
          dependencies: clean_list(row["dependencies"], 40).freeze
        )
      rescue ArgumentError, TypeError
        nil
      end

      def route_score(route, objective:)
        objective_tokens = objective.to_s.downcase.scan(/[a-z0-9]{4,}/).reject { |token| %w[then work with from that this].include?(token) }
        relevant = objective_tokens.empty? || objective_tokens.any? do |token|
          route.actions.any? { |action| action.downcase.include?(token) }
        end
        relevance = relevant ? 1.0 : 0.8
        reversible = { "easy" => 1.0, "moderate" => 0.8, "hard" => 0.55 }.fetch(route.reversibility)
        evidence_quality = [route.evidence_ids.size / 3.0, 1.0].min
        reinforcement = history.select { |row| row["route_id"] == route.id && row["verified"] }
          .sum { |row| row["reinforcement"].to_f }
        learned = 1.0 + [[reinforcement, -3.0].max, 3.0].min * 0.08
        mission_gravity = 0.5 + route.priority
        ((route.impact * route.confidence * relevance * reversible * mission_gravity *
          (0.5 + evidence_quality * 0.5) * learned) /
          (route.cost * (1.0 + route.risk * 2.0))).clamp(0.0, 100.0)
      end

      def route_explanation(route)
        prior = history.count { |row| row["route_id"] == route.id && row["verified"] }
        "grounded_evidence=#{route.evidence_ids.size}; mission_priority=#{route.priority}; " \
          "verified_outcomes=#{prior}; dependencies=#{route.dependencies.size}; reversible=#{route.reversibility}"
      end

      def underexplored?(route)
        history.count { |row| row["route_id"] == route.id && row["verified"] } < 2
      end

      def clean_list(value, limit)
        Array(value).map { |item| item.to_s.strip }.reject(&:empty?).uniq.first(limit)
      end

      def bounded_number(value, minimum, maximum)
        number = Float(value)
        raise ArgumentError, "non-finite route score input" unless number.finite?

        number.clamp(minimum, maximum)
      end
    end
  end
end
