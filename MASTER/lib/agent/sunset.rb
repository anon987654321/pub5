# frozen_string_literal: true

# bin/master sunset - knowing when to stop.
#
# The capstone: once everything is measured and predicted and pruned, the
# runtime recognizes when governance costs more than it returns and
# proposes dissolving the ceremony that no longer earns its place -
# including, where a simpler contract would serve better, its own role as
# a constitution. The report ranks cost against catch from the ledgers;
# the ruling is the operator's, recorded like any precedent. A constitution
# that cannot shrink toward what actually catches defects becomes the thing
# it exists to prevent.

require "yaml"
require_relative "fast_gate"

module Master
  module Agent
    module Sunset
      extend Base

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          case action
          when "report" then report
          when "retire" then retire(argv.drop(1))
          else
            puts "usage: bin/master sunset report | sunset retire ID --evidence R"
            exit(64)
          end
        end

        def ledger
          @ledger ||= load_yaml(data_path("sunset.yml")).fetch("ceremonies", [])
        end

        def save(rows)
          File.write(data_path("sunset.yml"), YAML.dump({ "schema" => 1, "ceremonies" => rows }))
        end

        def report
          rows = ledger.map do |row|
            cost = row["cost_minutes_per_landing"].to_f
            catches = row["measured_catches"].to_s
            value = catch_score(catches, row["status"])
            row.merge("rank" => { "cost_minutes" => cost, "catch_weight" => value,
                                  "advice" => advice(cost, value, catches) })
          end.sort_by { |r| [r.dig("rank", "catch_weight"), -r.dig("rank", "cost_minutes")] }

          emit(
            command: "sunset report",
            ceremonies: rows.size,
            ranked: rows,
            note: "rank 0 catch-weight with standing cost is a retire candidate; the ruling is the operator's, recorded as a precedent. This tier and the fast gate are themselves rows: the final ratchet turns on the ratchet.",
          )
          0
        end

        # A dry, exact catch weight: instrument readings and named catches
        # earn weight; prose-only claims of value earn none.
        def catch_score(catches, status)
          return 0.0 if status == "retired"
          return 1.0 if catches.match?(/\d+/)
          return 0.5 if catches.match?(/log|ledger|reading|count/i)

          0.0
        end

        def advice(cost, value, catches)
          if value.zero? && cost.positive?
            "retire candidate: standing cost, no counted catch; name the evidence that would revive it before dissolving"
          elsif value.positive? && cost > 10
            "keep, but make cheaper: the catch is counted, the cost is the largest in the ledger"
          elsif value.positive?
            "earns its place"
          else
            "run it deliberately and record the catch, or it is a ceremony"
          end
        end

        def retire(argv)
          flags = argv.each_with_index.filter_map { |a, i| a == "--evidence" ? [a, argv[i + 1]] : nil }.to_h
          id = argv.find { |a| a.match?(/[\w-]+/) && !a.start_with?("--") }
          refuse("sunset retire", "no ceremony id given", "an id from sunset report, e.g. falsification-harness") if id.nil?
          refuse("sunset retire", "retiring without evidence is a silent preference",
                 "--evidence R names the measurement that says the ceremony stopped earning its place") if flags["--evidence"].nil?

          row = ledger.find { |c| c["id"] == id }
          refuse("sunset retire", "nothing named #{id}", "sunset report ranks the ledger") if row.nil?
          row["status"] = "retired"
          row["retired_with_evidence"] = flags["--evidence"]
          row["retired_at"] = Time.now.utc.strftime("%Y-%m-%d")
          save(ledger)
          emit(command: "sunset retire", ceremony: id, status: "retired", evidence: flags["--evidence"],
               note: "record it as a precedent too: bin/master precedent overrule P-XXX --reason ... if the ceremony was itself a ruling")
          0
        end
      end
    end
  end
end
