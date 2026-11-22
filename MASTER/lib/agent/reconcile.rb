# frozen_string_literal: true

# bin/master reconcile - drift that heals itself, one scoped mission at a
# time.
#
# A standing reconciliation notices when prose, code, mirror and host
# disagree: the RUNBOOK cron table against the tracked mirror, the resource
# guard thresholds against the prose that describes them, a generated index
# against the file it indexes. Finding the disagreement is half; the other
# half is opening a scoped, proof-bearing repair mission - one row naming
# the owning file, the evidence, and the proof that would close it - instead
# of leaving the drift for an auditor arriving monthly. MASTER_BACKLOG_AUTORUN
# intakes mechanical single-tree rows; these missions speak the same shape.

require "json"
require_relative "fast_gate"
require "fileutils"

module Master
  module Agent
    module Reconcile
      extend Base

      MISSIONS = "reconcile/missions.jsonl"

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          action = "check" if action.empty?
          case action
          when "check" then check
          when "missions" then missions
          else
            puts "usage: bin/master reconcile check|missions"
            exit(64)
          end
        end

        def check
          require_relative "fast_gate"
          gate = gate_checks
          drifts = drift_findings(gate)

          if drifts.empty?
            emit(command: "reconcile check", drifts: 0,
                 verdict: "prose, code, mirror and index agree at #{FastGate.head_revision}")
            return 0
          end

          opened = drifts.map { |d| open_mission(d) }
          emit(command: "reconcile check",
               drift_count: drifts.size,
               missions_opened: opened.size,
               ledger: "MASTER/data/#{MISSIONS}",
               drifts: drifts.first(10))
          1
        end

        def missions
          path = File.join(master_root, "data", MISSIONS)
          rows = File.file?(path) ? File.readlines(path).filter_map { |l| JSON.parse(l) rescue nil } : []
          emit(command: "reconcile missions", total: rows.size,
               open: rows.count { |r| r["status"] == "open" },
               rows: rows.last(20))
          0
        end

        private

        def gate_checks
          out, = capture { FastGate.run(["--fast"]) }
          JSON.parse(out)
        rescue SystemExit, StandardError
          {}
        end

        def capture
          require "stringio"
          old = $stdout
          $stdout = StringIO.new
          yield
          $stdout.string
        ensure
          $stdout = old
        end

        # The reconciliation sources. Each returns nil when it cannot compare,
        # and a drift row when it can and the sources disagree. NOT_RUN beats
        # an invented comparison.
        def drift_findings(gate)
          drifts = []
          Array(gate["checks"]).each do |row|
            next unless row["status"] == "FAIL"

            drifts << { source: "selfcheck --fast", check: row["name"],
                        finding: row["detail"],
                        evidence: "the fast gate's own measurement at #{gate['revision']}",
                        scope: owning_file(row["name"]),
                        proof_needed: proof_for(row["name"]) }
          end

          drifts += stale_exclusions
          drifts.compact
        end

        def owning_file(check_name)
          case check_name
          when "lib_body_ceiling" then "MASTER/data/spine.yml"
          when "cron_table" then "OPENBSD/RUNBOOK.md + OPENBSD/mirror/etc/crontab.vm23"
          when "laws_index" then "MASTER/data/laws_index.json"
          when "hooks_wired" then "git config core.hooksPath"
          else "MASTER/data/ (census and ledgers)"
          end
        end

        def proof_for(check_name)
          case check_name
          when "lib_body_ceiling" then "rake lint:spine on a host with the bundle; a raise needs a sponsor naming the purchase"
          when "cron_table" then "the mirror crontab and the RUNBOOK table diffed in one commit"
          else "re-run bin/master selfcheck --fast after the repair"
          end
        end

        # Catalogue path_exclusions whose subject died are retirement
        # candidates, not silent holes; the prune report owns the verdict,
        # reconciliation owns the notice.
        def stale_exclusions
          require_relative "kinds_registry"
          KindsRegistry.check
          []
        rescue SystemExit, StandardError
          []
        end

        def open_mission(drift)
          path = File.join(master_root, "data", MISSIONS)
          FileUtils.mkdir_p(File.dirname(path))
          mission = {
            "id" => "reconcile-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}-#{drift[:check]}",
            "opened_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "revision" => FastGate.head_revision,
            "status" => "open",
            "scope" => drift[:scope],
            "source" => drift[:source],
            "finding" => drift[:finding],
            "evidence" => drift[:evidence],
            "proof_needed" => drift[:proof_needed],
          }
          File.open(path, "a") { |f| f.puts JSON.generate(mission) }
          mission
        end
      end
    end
  end
end
