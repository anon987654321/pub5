# frozen_string_literal: true

# bin/master falsify - the standing falsification harness.
#
# The README states the hypothesis: governed delivery holds quality where
# ungoverned automation cannot. The falsification is /fix failing to hold
# this tree's ratchets green over time. This harness runs that experiment
# for real, in miniature and continuously: the same incoming change traffic
# (the laws' own bad fixtures - defects with provenance) through two lanes.
# The governed lane measures, refuses the defect, repairs it against the
# law's good fixture, and re-measures. The ungoverned lane accepts the
# change as it arrived. Defect survival, ratchet drift and time to verified
# remediation are the instrument readings; each run appends one JSONL row
# stamped with the revision, so the thesis is a reading, not a paragraph.
#
# `falsify run` performs the experiment. `falsify status` prints the latest
# reading and the trend. Both are honest about scope: this is the lexical
# corpus on synthetic traffic, not the whole runtime on live traffic - and
# that scope is named in every reading.

require "json"
require_relative "fast_gate"
require "tmpdir"
require "fileutils"

module Master
  module Agent
    module Falsify
      extend Base

      READINGS = "falsification/readings.jsonl"

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          action = "status" if action.empty?
          case action
          when "run" then run_experiment
          when "status" then status
          else
            puts "usage: bin/master falsify run|status"
            exit(64)
          end
        end

        def run_experiment
          require_relative "bare_scan"
          corpus = BareScan.load_corpus("lexical")
          defects = corpus.laws.filter_map do |id, row|
            bad = row.fetch(:builder).meta[:bad]
            good = row.fetch(:builder).meta[:good]
            next nil if bad.nil? || good.nil?

            # A law proves its fixtures at the path it declares (example_path):
            # DEBUG_OUTPUT judges /lib/, TIME_ZONE_UNSAFE judges /app/. Traffic
            # that ignores the reach is not the law's own proof condition.
            example = row.fetch(:builder).meta[:example_path].to_s.delete_prefix("/")
            relative = example.empty? ? "repo/lib/incoming.rb" : example
            { law: id, bad:, good:, severity: row.fetch(:entry)["severity"], relative: }
          end
          refuse("falsify run", "the corpus exposes no fixture pair to traffic",
                 "laws with bad and good fixtures; rake dogfood is the full provenance") if defects.empty?

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          governed = { blocked: 0, repaired: 0, remediation_steps: 0, escaped: 0 }
          ungoverned = { accepted: 0, survived: 0 }
          drift_before = drift_after = 0

          defects.each do |defect|
            Dir.mktmpdir do |dir|
              subject = File.join(dir, defect[:relative])
              FileUtils.mkdir_p(File.dirname(subject))

              # Lane A, ungoverned: the change lands as it arrived.
              File.write(subject, defect[:bad])
              ungoverned[:accepted] += 1
              ungoverned[:survived] += 1 if corpus.scan_file(subject).any? { |f| f[:law] == defect[:law] }

              # Lane B, governed: measure, refuse, repair, measure again.
              File.write(subject, defect[:bad])
              first = corpus.scan_file(subject)
              drift_before += first.size
              if first.any? { |f| f[:law] == defect[:law] }
                governed[:blocked] += 1
                File.write(subject, defect[:good])
                governed[:remediation_steps] += 1
                second = corpus.scan_file(subject)
                drift_after += second.size
                if second.any? { |f| f[:law] == defect[:law] }
                  governed[:escaped] += 1
                else
                  governed[:repaired] += 1
                end
              else
                governed[:escaped] += 1
                governed[:remediation_steps] += 1
              end
            end
          end

          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
          reading = {
            "at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "revision" => FastGate.head_revision,
            "scope" => "lexical corpus, synthetic fixture traffic",
            "traffic_size" => defects.size,
            "ungoverned" => ungoverned.merge(defect_survival: ratio(ungoverned[:survived], ungoverned[:accepted])),
            "governed" => governed.merge(
              held_quality: ratio(governed[:repaired], governed[:blocked] + governed[:escaped]),
              avg_remediation_steps: ratio(governed[:remediation_steps], defects.size),
            ),
            "ratchet_drift" => { ungoverned_lane_findings: drift_before, after_governed_repair: drift_after },
            "elapsed_s" => elapsed,
          }
          path = File.join(master_root, "data", READINGS)
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") { |f| f.puts JSON.generate(reading) }
          emit(command: "falsify run", reading:)
          governed[:escaped].zero? ? 0 : 1
        end

        def status
          path = File.join(master_root, "data", READINGS)
          rows = File.file?(path) ? File.readlines(path).filter_map { |l| JSON.parse(l) } : []
          if rows.empty?
            emit(command: "falsify status", readings: 0,
                 note: "no reading yet; run bin/master falsify run to take the first instrument reading")
            return 0
          end

          latest = rows.last
          survival_trend = rows.map { |r| r["ungoverned"]["defect_survival"] }
          held_trend = rows.map { |r| r["governed"]["held_quality"] }
          emit(command: "falsify status",
               readings: rows.size,
               latest:,
               trend: {
                 ungoverned_defect_survival: survival_trend,
                 governed_held_quality: held_trend,
               },
               thesis: "governed delivery holds quality where ungoverned automation cannot; " \
                       "each reading above is one run of that experiment at this revision")
          0
        end

        private

        def ratio(numerator, denominator)
          return 0.0 if denominator.zero?

          (numerator.to_f / denominator).round(4)
        end
      end
    end
  end
end
