# frozen_string_literal: true

module Master
  module Fix
    # Evidence-bounded route selection for /fix. This planner never mutates the
    # repository: Kernel, TaskContract, Transaction and verification remain the
    # only execution authority.
    class AdaptiveJourney
      TERMINAL_STATES = %w[PASS FAIL INCONCLUSIVE BLOCKED TIMEOUT DELIVERY_FAILED].freeze
      LEARNABLE_STATES = %w[PASS FAIL].freeze
      DEFAULT_EXPLORATION = 0.12
      MAX_HISTORY = 500

      Route = Data.define(:id, :actions, :evidence_ids, :impact, :confidence, :cost,
                          :risk, :reversibility, :causes, :preserves)
      Decision = Data.define(:route, :score, :reason, :alternatives, :exploration)

      attr_reader :history, :exploration_rate

      def initialize(history: [], exploration_rate: DEFAULT_EXPLORATION)
        @history = normalize_history(history).last(MAX_HISTORY).freeze
        @exploration_rate = Float(exploration_rate).clamp(0.0, 0.5)
        freeze
      end

      # Evidence IDs must occur in verified_evidence. Unsupported model claims
      # cannot earn weight or make a route eligible.
      def choose(routes:, verified_evidence:, objective:, exploration: true)
        evidence = normalize_evidence(verified_evidence)
        candidates = Array(routes).filter_map { |row| normalize_route(row, evidence) }
        raise ArgumentError, "no route has grounded evidence and valid constraints" if candidates.empty?

        ranked = candidates.map { |route| [route, route_score(route, objective:), route_explanation(route)] }
          .sort_by { |route, score, _| [-score, route.id] }
        selected = ranked.first
        if exploration && ranked.size > 1 && underexplored?(ranked.first[0])
          alternative = ranked.drop(1).find { |row| underexplored?(row[0]) }
          selected = alternative if alternative && alternative[1] >= ranked.first[1] * (1.0 - @exploration_rate)
        end

        route, score, reason = selected
        Decision.new(
          route:, score: score.round(4), reason:,
          alternatives: ranked.reject { |row| row[0].id == route.id }.first(5).map do |candidate, value, why|
            { id: candidate.id, score: value.round(4), reason: why }.freeze
          end.freeze,
          exploration: route.id != ranked.first[0].id
        )
      end

      # Only verified PASS/FAIL evidence reinforces or penalizes a route.
      # Other terminal states remain visible as negative knowledge with zero weight.
      def observe(route_id:, status:, evidence_id:, verified:)
        state = status.to_s.upcase
        raise ArgumentError, "unknown journey outcome: #{state}" unless TERMINAL_STATES.include?(state)

        proof = evidence_id.to_s.strip
        learnable = verified == true && LEARNABLE_STATES.include?(state) && !proof.empty?
        row = {
          "route_id" => route_id.to_s, "status" => state,
          "evidence_id" => proof.empty? ? nil : proof, "verified" => learnable,
          "reinforcement" => learnable ? (state == "PASS" ? 1.0 : -1.0) : 0.0,
        }
        self.class.new(history: (history + [row]).last(MAX_HISTORY), exploration_rate:)
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
          "nodes" => nodes.sort.to_h.freeze, "edges" => valid_edges.freeze,
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
          next if id.empty? || !TERMINAL_STATES.include?(state)
          verified = row["verified"] == true && LEARNABLE_STATES.include?(state) &&
                     !row["evidence_id"].to_s.strip.empty?
          {
            "route_id" => id, "status" => state,
            "evidence_id" => verified ? row["evidence_id"].to_s : nil,
            "verified" => verified,
            "reinforcement" => verified ? (state == "PASS" ? 1.0 : -1.0) : 0.0,
          }.freeze
        end
      end

      def normalize_evidence(rows)
        Array(rows).each_with_object({}) do |raw, result|
          next unless raw.is_a?(Hash)
          row = raw.transform_keys(&:to_s)
          id = row["id"].to_s.strip
          result[id] = row.freeze if !id.empty? && row["verified"] == true
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
        cost = bounded_number(row["cost"], 0.01, 100.0)
        risk = bounded_number(row["risk"], 0.0, 1.0)
        return unless %w[easy moderate hard].include?(row["reversibility"].to_s)

        Route.new(id:, actions: actions.freeze, evidence_ids: evidence_ids.freeze,
          impact:, confidence:, cost:, risk:, reversibility: row["reversibility"].to_s,
          causes: clean_list(row["causes"], 12).freeze,
          preserves: clean_list(row["preserves"], 12).freeze)
      rescue ArgumentError, TypeError
        nil
      end

      def route_score(route, objective:)
        relevant = objective.to_s.empty? || route.actions.any? { |a| a.downcase.include?(objective.to_s.downcase) }
        relevance = relevant ? 1.0 : 0.8
        reversible = { "easy" => 1.0, "moderate" => 0.8, "hard" => 0.55 }.fetch(route.reversibility)
        evidence_quality = [route.evidence_ids.size / 3.0, 1.0].min
        reinforcement = history.select { |r| r["route_id"] == route.id && r["verified"] }
          .sum { |r| r["reinforcement"].to_f }
        learned = 1.0 + [[reinforcement, -3.0].max, 3.0].min * 0.08
        ((route.impact * route.confidence * relevance * reversible *
          (0.5 + evidence_quality * 0.5) * learned) /
          (route.cost * (1.0 + route.risk * 2.0))).clamp(0.0, 100.0)
      end

      def route_explanation(route)
        "grounded_evidence=#{route.evidence_ids.size}; verified_outcomes=#{history.count { |r| r["route_id"] == route.id && r["verified"] }}; reversible=#{route.reversibility}"
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
