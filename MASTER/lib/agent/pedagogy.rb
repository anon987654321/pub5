# frozen_string_literal: true

# bin/master pedagogy propose - a pedagogy that runs both ways.
#
# Once the operator's taste accumulates, the tree should help the operator
# govern, not only obey. This command surfaces the pattern in their own
# rulings - you have consistently chosen X, here is the evidence - and
# proposes new laws born from repeated judgments, always as proposals,
# never as usurpation: rows land in the refutation ledger with state open
# and source pedagogy, so the tree's own convergence machinery reads them
# like any other proposal. The model only proposes the operator's own
# better principles back to them, with the receipts attached.

require "yaml"
require_relative "fast_gate"

module Master
  module Agent
    module Pedagogy
      extend Base

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          action = "propose" if action.empty?
          case action
          when "propose" then propose
          when "patterns" then patterns
          else
            puts "usage: bin/master pedagogy propose|patterns"
            exit(64)
          end
        end

        def patterns
          taste = load_yaml(data_path("taste_ledger.yml")).fetch("decisions", [])
          rulings = load_yaml(data_path("precedents.yml")).fetch("precedents", [])
          grouped = taste.group_by { |d| [d["domain"], d["decision"]] }
          emit(command: "pedagogy patterns",
               taste_decisions: taste.size,
               recorded_rulings: rulings.size,
               patterns: grouped.filter_map do |(domain, decision), rows|
                next nil if rows.size < 2

                { domain:, decision:, count: rows.size,
                  subjects: rows.map { |r| r["subject"] }.first(4),
                  evidence: rows.map { |r| r["revision"] }.compact }
              end)
          0
        end

        def propose
          taste = load_yaml(data_path("taste_ledger.yml")).fetch("decisions", [])
          grouped = taste.group_by { |d| [d["domain"], d["decision"]] }
          proposals = grouped.filter_map do |(domain, decision), rows|
            next nil if rows.size < 3

            {
              "id" => "pedagogy-#{domain}-#{decision}-#{Time.now.utc.strftime('%Y%m%d')}",
              "tree" => "MASTER",
              "state" => "open",
              "claim" => "codify the operator's recorded #{decision} pattern in #{domain}: #{rows.map { |r| r['subject'] }.first(2).join('; ')}",
              "reason" => "born from #{rows.size} recorded operator decisions (#{rows.map { |r| r['at'] }.join(', ')}), surfaced by bin/master pedagogy propose; always a proposal, never a usurpation",
              "proposed_by" => "pedagogy",
            }
          end

          if proposals.empty?
            emit(command: "pedagogy propose",
                 proposals: 0,
                 note: "a law proposal needs at least three recorded decisions in one domain; the operator's rulings accumulate first, the proposal follows")
            return 0
          end

          ledger_path = data_path("proposals.yml")
          ledger = load_yaml(ledger_path)
          existing = ledger.fetch("proposals", []).map { |p| p["id"] }
          fresh = proposals.reject { |p| existing.include?(p["id"]) }
          if fresh.empty?
            emit(command: "pedagogy propose", proposals: 0, note: "the accumulated pattern is already proposed; the ledger holds it")
            return 0
          end

          ledger["proposals"] = (ledger.fetch("proposals", []) + fresh)
          File.write(ledger_path, YAML.dump(ledger))
          emit(command: "pedagogy propose", proposals: fresh.size, rows: fresh,
               note: "rows landed in the refutation ledger with state open; the convergence machinery reads them like any other proposal")
          0
        end
      end
    end
  end
end
