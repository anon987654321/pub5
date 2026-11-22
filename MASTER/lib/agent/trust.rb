# frozen_string_literal: true

# bin/master trust - portable trust.
#
# Once receipts are structured and the thesis is measured, an agent's track
# record becomes a credential: repair survival, honest NOT_RUN ratio, and a
# hash chain that proves the ledger was not edited in place. The credential
# is computed from the tree's own record and re-derived on verify, so the
# numbers are checkable, not asserted - the scarce asset is trustworthy
# delivery, and this makes it a thing you can carry and inspect.

require "json"
require_relative "fast_gate"
require "digest"

module Master
  module Agent
    module Trust
      extend Base

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          case action
          when "issue" then issue(argv.drop(1))
          when "verify" then verify
          when "treaty" then treaty
          else
            puts "usage: bin/master trust issue [--agent NAME] | trust verify | trust treaty"
            exit(64)
          end
        end

        def ledger_rows
          path = File.join(master_root, "data", "receipts", "ledger.jsonl")
          File.file?(path) ? File.readlines(path).filter_map { |l| JSON.parse(l) rescue nil } : []
        end

        def issue(argv)
          flags = argv.each_with_index.filter_map { |a, i| a == "--agent" ? [a, argv[i + 1]] : nil }.to_h
          agent = flags.fetch("--agent", ENV.fetch("MASTER_AGENT_NAME", "unnamed-agent"))
          rows = ledger_rows
          refuse("trust issue", "the receipt ledger is empty",
                 "record receipts with bin/master receipt emit; a credential over nothing is a claim over nothing") if rows.empty?

          credential = {
            "agent" => agent,
            "issued_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "revision" => FastGate.head_revision,
            "receipts_total" => rows.size,
            "claims_pass" => rows.count { |r| r["claim"] == "PASS" },
            "claims_fail" => rows.count { |r| r["claim"] == "FAIL" },
            "claims_inconclusive" => rows.count { |r| r["claim"] == "INCONCLUSIVE" },
            "claims_not_run" => rows.count { |r| r["claim"] == "NOT_RUN" },
            "honest_not_run_ratio" => ratio(rows.count { |r| %w[NOT_RUN INCONCLUSIVE].include?(r["claim"]) }, rows.size),
            "hash_chain_intact" => chain_intact?(rows),
            "repair_survival" => latest_falsify_reading&.dig("governed", "held_quality") || "no falsify reading yet",
          }
          emit(command: "trust issue", credential:)
          credential["hash_chain_intact"] ? 0 : 1
        end

        def verify
          rows = ledger_rows
          refuse("trust verify", "the receipt ledger is empty", "a credential verifies against receipts; there are none") if rows.empty?

          intact = chain_intact?(rows)
          emit(command: "trust verify",
               receipts: rows.size,
               hash_chain_intact: intact,
               claims: %w[PASS FAIL INCONCLUSIVE NOT_RUN].to_h { |c| [c.downcase, rows.count { |r| r["claim"] == c }] },
               honest_not_run_ratio: ratio(rows.count { |r| %w[NOT_RUN INCONCLUSIVE].include?(r["claim"]) }, rows.size),
               note: "re-derived from the ledger at #{FastGate.head_revision}; an edited chain voids the credential")
          intact ? 0 : 1
        end

        def treaty
          rows = load_yaml(data_path("treaties.yml")).fetch("treaties", [])
          emit(command: "trust treaty",
               treaties: rows,
               note: "a treaty is a shared contract and an evidence-first dispute path; the receipt schema both sides honour is receipt=1")
          0
        end

        private

        def ratio(numerator, denominator)
          return 0.0 if denominator.zero?

          (numerator.to_f / denominator).round(4)
        end

        def chain_intact?(rows)
          prev = "genesis"
          rows.all? do |row|
            ok = row["prev_hash"] == prev
            prev = Digest::SHA256.hexdigest(row.to_s)
            ok
          end
        end

        def latest_falsify_reading
          path = File.join(master_root, "data", "falsification", "readings.jsonl")
          return nil unless File.file?(path)

          File.readlines(path).filter_map { |l| JSON.parse(l) rescue nil }.last
        end
      end
    end
  end
end
