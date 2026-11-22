# frozen_string_literal: true

module Master
  module Fix
    class ArchitectureExploration
      # The operator-facing rendering of a persisted tree row, re-opening the
      # class defined in fix/architecture_exploration.rb: the brief the report
      # carries for a winner and for an inconclusive tournament. All private;
      # the public surface stays in fix/architecture_exploration.rb.
      private

      def brief(row)
        output = ["ARCHITECTURE EXPLORATION #{row["status"]}: #{row["tree"]} accepted #{row["accepted"]}/#{row["requested"]}. Runtime tests: NOT_RUN."]
        if row["winner"]
          winner_brief(row, output)
        else
          no_winner_brief(row, output)
        end
        output.join("\n")
      end

      def winner_brief(row, output)
        winner = row["winner"]
        output << "Direction #{winner["id"]}: #{winner["title"]}; score=#{winner["score"]}/100."
        output << "Thesis: #{winner["thesis"]}"
        output << "Boundary: #{winner["core_boundary"]}"
        output << "Source evidence: #{winner["evidence_paths"].join(", ")}"
        output << "Test anchors (not executed): #{winner["test_paths"].join(", ")}"
        output << "Verification: #{winner["verification_plan"]}"
        output << "Benefits: #{winner["benefits"].join("; ")}"
        output << "Trade-offs: #{winner["tradeoffs"].join("; ")}"
        output << "Risks: #{winner["risks"].join("; ")}"
        output << "Rollback: #{winner["rollback_plan"]}"
        row["shortlist"].drop(1).each do |item|
          output << "Alternative #{item["id"]}: #{item["title"]}; score=#{item["score"]}/100."
        end
        tournament_brief(row, output)
      end

      def tournament_brief(row, output)
        decision = row["decision"] || {}
        output << "Tournament evidence: distinct_path_sets=#{decision["distinct_change_path_sets"]}; " \
          "qualified=#{decision["qualified_candidates"]}; winner_margin=#{decision["winner_margin"] || "unavailable"}; " \
          "execution_proof=#{decision["execution_proof"] || "NOT_RUN"}."
        output << "Selected direction guides narrow repairs and is not authorization for broad rewrites."
      end

      def no_winner_brief(row, output)
        reason = if row["accepted"].to_i < MIN_CANDIDATES
                   "fewer than #{MIN_CANDIDATES} distinct grounded plans survived"
                 else
                   "fewer than #{MIN_QUALIFIED_CANDIDATES} plans passed the evidence/quality gate"
                 end
        output << "No winner: #{reason}. State is INCONCLUSIVE."
        row["shortlist"].first(3).each do |item|
          output << "Unselected candidate #{item["id"]}: #{item["title"]}; score=#{item["score"]}/100."
        end
      end
    end
  end
end
