# frozen_string_literal: true

# bin/master receipt - structured evidence a landing can hand back.
#
# Proof vocabulary existed; it was a wall, not a conversation. A receipt is
# the two-way form: an outside agent records what it measured (a command and
# its exit, a scanner run, a diff that changes comments only), this validator
# answers whether the evidence supports the claim, and for INCONCLUSIVE it
# names the cheapest next measurement that would turn it into a PASS.
# Recorded receipts append to a hash-chained ledger, which is also the raw
# material the trust credentials (bin/master trust) are computed from.

require "json"
require "digest"
require "open3"

module Master
  module Agent
    module Receipts
      extend Base

      LEDGER = "receipts/ledger.jsonl"

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          case action
          when "emit" then emit_receipt(argv.drop(1))
          when "validate" then validate(argv.drop(1))
          when "ledger" then ledger
          else
            puts "usage: bin/master receipt emit --law ID --subject PATH --exit N [--cmd S] | receipt validate FILE | receipt ledger"
            exit(64)
          end
        end

        # A receipt is built from what actually ran. Nothing here executes a
        # measurement; it records one that happened and vouches for nothing
        # it did not see.
        def emit_receipt(argv)
          opts = parse_flags(argv, %w[--law --subject --cmd --exit --kind --note])
          law = opts["--law"]
          subject = opts["--subject"]
          refuse("receipt emit", "no law given", "the law id the evidence speaks to, e.g. --law NO_DEBUG") if law.nil?
          refuse("receipt emit", "no subject given", "the path the measurement is about, e.g. --subject lib/agent") if subject.nil?

          receipt = {
            "receipt" => "1",
            "law" => law,
            "subject" => subject,
            "evidence" => {
              "kind" => opts.fetch("--kind", "shell"),
              "command" => opts["--cmd"],
              "exit" => opts["--exit"]&.to_i,
            },
            "claim" => claim_for(opts["--exit"]),
            "measured_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "revision" => FastGate.head_revision,
            "note" => opts["--note"],
          }
          receipt.delete_if { |_k, v| v.nil? }
          append_ledger(receipt) if ENV["MASTER_RECEIPT_RECORD"] != "0"
          emit(receipt)
          receipt["claim"] == "PASS" ? 0 : 1
        end

        def claim_for(exit_code)
          case exit_code&.to_i
          when 0 then "PASS"
          when nil then "INCONCLUSIVE"
          else "FAIL"
          end
        end

        def validate(argv)
          file = argv.first
          refuse("receipt validate", "no receipt file given", "a JSON receipt from receipt emit, or - for stdin") if file.nil?

          raw = file == "-" ? $stdin.read : File.read(file)
          receipt = JSON.parse(raw)
          issues = []
          law_id = receipt["law"]

          require_relative "law_index"
          row = LawIndex.index.fetch("laws", {})[law_id]
          issues << "unknown law #{law_id}" if row.nil?
          issues << "subject missing from the working tree" unless File.exist?(File.expand_path(receipt["subject"].to_s, repo_root))

          evidence = receipt.fetch("evidence", {})
          claim = receipt["claim"]
          case claim
          when "PASS"
            issues << "a PASS needs executable evidence: a command with its exit, or a scanner run" unless evidence["exit"].is_a?(Integer) || evidence["kind"] == "scanner"
            issues << "exit #{evidence['exit']} does not support a PASS claim" if evidence["exit"].is_a?(Integer) && evidence["exit"] != 0
          when "FAIL"
            issues << "a FAIL needs the exit or the findings that refused the claim" unless evidence["exit"].is_a?(Integer) || evidence["kind"] == "scanner"
          when "NOT_RUN"
            issues << "a NOT_RUN must say why" if receipt["note"].to_s.empty? && evidence["why"].to_s.empty?
          when "INCONCLUSIVE"
            issues << nil
          else
            issues << "claim must be PASS, FAIL, INCONCLUSIVE or NOT_RUN"
          end
          issues.compact!

          answer = {
            command: "receipt validate",
            verdict: issues.empty? ? "VALID" : "INVALID",
            issues:,
          }
          if claim == "INCONCLUSIVE"
            answer[:cheapest_next_measurement] = next_measurement(law_id, receipt["subject"])
            answer[:note] = "INCONCLUSIVE is not a failure and not a pass; the measurement above is the cheapest way out"
          end
          emit(answer)
          issues.empty? ? 0 : 1
        end

        # The cheapest way out of an inconclusive, named by the law's own
        # machinery: a lexical law proves itself on its fixtures in seconds;
        # anything rendered or semantic says so instead of pretending.
        def next_measurement(law_id, subject)
          require_relative "law_index"
          row = LawIndex.index.fetch("laws", {}).fetch(law_id, nil)
          return "run bin/master scan --bare #{subject} and attach the findings" if row.nil?

          if row["bare_detector"]
            "bin/master scan --bare #{subject} --laws #{law_id} - seconds, no bundle; " \
              "exit 0 with no findings turns this receipt into a PASS"
          elsif row.dig("fixtures")
            "replay the law's own fixture pair from laws_index.json against the subject"
          else
            "no bare detector: this law needs the #{row['mode']} lane of the full runtime " \
              "(rendered or semantic); leave the receipt NOT_RUN with the reason rather than claiming a PASS"
          end
        end

        def ledger
          path = File.join(master_root, "data", LEDGER)
          rows = File.file?(path) ? File.readlines(path).map { |l| JSON.parse(l) } : []
          emit(command: "receipt ledger", receipts: rows.size, path: "MASTER/data/#{LEDGER}", rows: rows.last(10))
          0
        end

        private

        def parse_flags(argv, flags)
          opts = {}
          argv.each_with_index do |arg, i|
            next unless flags.include?(arg)

            opts[arg] = argv[i + 1]
          end
          opts
        end

        # Hash-chained: each row carries the digest of the previous one, so
        # the track record an agent builds (bin/master trust) cannot be edited
        # in place without the chain noticing.
        def append_ledger(receipt)
          path = File.join(master_root, "data", LEDGER)
          FileUtils.mkdir_p(File.dirname(path))
          prev = File.file?(path) ? File.readlines(path).last.to_s.strip : ""
          receipt["prev_hash"] = prev.empty? ? "genesis" : Digest::SHA256.hexdigest(prev)
          File.open(path, "a") { |f| f.puts JSON.generate(receipt) }
        rescue StandardError => e
          warn "receipt: ledger append failed (#{e.message}); the receipt still validates, the record does not grow"
        end
      end
    end
  end
end
