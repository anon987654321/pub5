# frozen_string_literal: true

# bin/master prune --report - laws pruned by measured value.
#
# The catalogue already retires laws that earned nothing; this makes
# retirement evidence-driven. A law that produces zero true findings across
# the recorded runs while costing review attention is a fold candidate; a
# law whose findings are mostly noise is a narrowing candidate. The
# evidence is the tree's own measurement record: data/self_findings.yml
# (findings per law at a recorded revision) plus one fresh bare pass. The
# report is advisory - RATCHET_INTEGRITY applies to the corpus itself, so a
# fold is the operator's ruling, recorded as a precedent, never a silent
# deletion.

require "yaml"
require_relative "fast_gate"

module Master
  module Agent
    module Prune
      extend Base

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          action = "report" if action.empty?
          case action
          when "report" then report
          else
            puts "usage: bin/master prune report"
            exit(64)
          end
        end

        def report
          recorded = recorded_baseline
          fresh = fresh_pass
          rows = candidates(recorded, fresh)

          emit(
            command: "prune report",
            recorded_baseline: recorded ? { revision: recorded["revision"] || "recorded", total: recorded["findings"], at: recorded["recorded_at"] } : nil,
            fresh_pass: { revision: FastGate.head_revision, laws: fresh.size, findings: fresh.values.sum },
            fold_candidates: rows[:fold],
            narrow_candidates: rows[:narrow],
            note: "a fold or a narrowing is the operator's ruling; record it as a precedent with its evidence, or leave the law standing",
          )
          0
        end

        # The tree's own recorded measurement. self_findings.yml is the
        # baseline the operator's ratchet calls wrote; a law with zero rows
        # across it has never earned a finding against the corpus it judged.
        def recorded_baseline
          @recorded_baseline ||= begin
            data = load_yaml(data_path("self_findings.yml"))
            { "findings" => data["findings"], "by_rule" => data["by_rule"] || {},
              "revision" => data["revision"], "recorded_at" => data["recorded_at"] }
          end
        end

        def fresh_pass
          require_relative "bare_scan"
          corpus = BareScan.load_corpus("lexical")
          paths = Dir.glob(File.join(master_root, "lib", "**", "*.rb")) +
                  Dir.glob(File.join(master_root, "bin", "*")).select { |f| File.file?(f) }
          counts = Hash.new(0)
          paths.each do |path|
            corpus.scan_file(path).each { |f| counts[f[:law]] += 1 }
          end
          counts
        rescue StandardError
          Hash.new(0)
        end

        def candidates(recorded, fresh)
          require_relative "bare_scan"
          corpus = BareScan.load_corpus("lexical")
          by_rule = recorded["by_rule"] || {}
          fold = []
          narrow = []

          # Only laws that were actually measured can be judged for value: a
          # semantic law with no bare detector is never-measured here, not
          # zero-value. The fresh pass is the reach; the recorded baseline is
          # the history.
          measured = corpus.laws.keys | by_rule.keys
          catalogue_entries.each do |id, entry|
            next unless entry.is_a?(Hash)
            next unless measured.include?(id)
            next if entry["lifecycle"] == "retired"

            recorded_count = by_rule[id] || 0
            fresh_count = fresh[id] || 0
            severity = entry["severity"]

            if recorded_count.zero? && fresh_count.zero?
              fold << { law: id, severity:, recorded_findings: 0, fresh_findings: 0,
                        why: "zero true findings across the recorded baseline and a fresh pass over MASTER's own Ruby; the attention it costs has no catch to show" }
            elsif severity == "info" && fresh_count.positive?
              narrow << { law: id, recorded_findings: recorded_count, fresh_findings: fresh_count,
                          why: "info-severity law with standing findings; candidates for scope narrowing, not deletion" }
            end
          end
          { fold: fold.first(25), narrow: narrow.first(15) }
        end
      end
    end
  end
end
