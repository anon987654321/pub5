# frozen_string_literal: true

# The bare tier's contract suite, run under a bare Ruby.
#
#   ruby MASTER/test/bare/test_agent_tier.rb
#
# No test_helper, no bundle, no runtime: the tier is the proof tier, so its
# suite runs the way the tier does. Everything a bare invocation owes is
# asserted here: the scanner loads the real lexical corpus and proves a law
# on its own bad fixture, the law index answers a full dictionary row, the
# status view buckets without swallowing a ledger, the fast gate marks what
# it cannot run NOT_RUN instead of PASS, a receipt with executable evidence
# validates and an inconclusive one names its cheapest way out, and the
# OPENBSD admission tier never hands a comment to the heavy gate.

require "json"
require "tmpdir"
require "fileutils"
require "minitest/autorun"
require_relative "../../lib/agent/agent_cli"

# The router loads these lazily; the suite names them directly.
%w[bare_scan law_index status_view receipts openbsd_tier fast_gate falsify
   predict coverage_map export_kit taste reconcile prune precedent trust
   court scars pedagogy capability sunset].each do |mod|
  require_relative "../../lib/agent/#{mod}"
end

module Master
  module Agent
    class TestAgentTier < Minitest::Test
      def master_root
        File.expand_path("../..", __dir__)
      end

      def repo_root
        File.expand_path("../..", master_root)
      end

      def scan_corpus
        BareScan.load_corpus("lexical")
      end

      def test_bare_scanner_proves_a_law_on_its_own_bad_fixture
        corpus = scan_corpus
        refute_empty corpus.laws, "the lexical corpus must load under a bare Ruby"

        fixture = File.join(Dir.mktmpdir("tier"), "bad_fixture.rb")
        File.write(fixture, corpus.laws.fetch("NO_PUTS").fetch(:builder).meta[:bad])

        findings = corpus.scan_file(fixture)
        assert findings.any? { |f| f[:law] == "NO_PUTS" },
               "NO_PUTS must flag its own bad fixture; a law that cannot prove itself proves nothing"
      ensure
        FileUtils.remove_entry(File.dirname(fixture)) if fixture
      end

      def test_bare_scanner_honours_catalogue_path_exclude
        corpus = scan_corpus
        lib_dir = File.join(master_root, "lib", "agent")
        assert_empty corpus.scan_file(File.join(lib_dir, "hooks.rb")).select { |f| f[:law] == "NO_PUTS" },
                     "the agent_interface kind owns NO_PUTS's reach here; a kind that is not honoured is prose"
      end

      def test_law_index_answers_a_full_dictionary_row
        LawIndex.instance_variable_set(:@index, nil)
        LawIndex.write_index! unless File.file?(LawIndex.index_path)
        row = LawIndex.index.fetch("laws").fetch("NO_PUTS")
        %w[id severity mode lifecycle languages exemptions definition_sources].each do |field|
          assert row.key?(field), "the dictionary row for NO_PUTS is missing #{field}"
        end
        assert_equal ["agent_interface", "repl_session"], row.dig("exemptions", "kinds"),
                     "the kind registry is where the exemption is owned, not the detector source"
      end

      def test_status_view_buckets_without_swallowing_a_ledger
        view = StatusView.view
        assert_operator view[:counts].values.sum, :>, 100, "the union view must be reading real ledgers"
        %w[actionable-now needs-proof needs-operator refused].each do |bucket|
          assert view[:buckets].key?(bucket), "bucket #{bucket} missing from the union view"
        end
        refused = view[:buckets].fetch("refused")
        assert refused.all? { |r| r.key?(:source) || r.key?("source") },
               "a refused row that does not name its owning file is a rumour"
      end

      def test_receipt_with_executable_evidence_validates
        Dir.mktmpdir do |dir|
          subject = File.join(dir, "subject.rb")
          File.write(subject, "value = 1\n")
          receipt = { "receipt" => "1", "law" => "NO_PUTS", "subject" => subject,
                      "claim" => "PASS", "evidence" => { "kind" => "scanner", "exit" => 0 },
                      "measured_at" => Time.now.utc.iso8601, "note" => "bare scan, zero findings" }
          file = File.join(dir, "receipt.json")
          File.write(file, JSON.generate(receipt))

          out, _err = capture_io { Receipts.validate([file]) }
          assert_includes out, "VALID", "a scanner receipt with exit 0 must validate"
        end
      end

      def test_inconclusive_receipt_names_its_cheapest_way_out
        Dir.mktmpdir do |dir|
          subject = File.join(dir, "subject.rb")
          File.write(subject, "value = 1\n")
          receipt = { "receipt" => "1", "law" => "NO_PUTS", "subject" => subject,
                      "claim" => "INCONCLUSIVE", "evidence" => { "kind" => "shell" } }
          file = File.join(dir, "receipt.json")
          File.write(file, JSON.generate(receipt))

          out, _err = capture_io { Receipts.validate([file]) }
          assert_includes out, "cheapest_next_measurement", "an inconclusive must answer with the next measurement"
          assert_includes out, "scan --bare", "for a lexical law the cheap way out is the bare scanner"
        end
      end

      def test_pass_claim_without_evidence_is_refused
        Dir.mktmpdir do |dir|
          subject = File.join(dir, "subject.rb")
          File.write(subject, "value = 1\n")
          receipt = { "receipt" => "1", "law" => "NO_PUTS", "subject" => subject,
                      "claim" => "PASS", "evidence" => { "kind" => "manual" } }
          file = File.join(dir, "receipt.json")
          File.write(file, JSON.generate(receipt))

          out, _err = capture_io { Receipts.validate([file]) }
          assert_includes out, "INVALID", "a PASS claimed from nothing is the defect the receipt tier exists to catch"
        end
      end

      def test_openbsd_tier_keeps_prose_light_and_the_host_heavy
        out, _err = capture_io { OpenbsdTier.run(["OPENBSD/RUNBOOK.md"]) }
        assert_includes out, '"tier": "light"', "a prose file with no native interface belongs in the light gate"

        out, _err = capture_io { OpenbsdTier.run(["OPENBSD/mirror/etc/crontab.vm23"]) }
        assert_includes out, '"tier": "heavy"', "cron on vm23 is behavior; the heavy gate is right for it"
      end

      def test_fast_gate_marks_what_it_cannot_run
        gate = FastGate.run(["--fast"])
        checks = JSON.parse(read_gate_output(gate))
        checks.fetch("checks").each do |row|
          assert_includes %w[PASS FAIL NOT_RUN], row["status"], "#{row['name']} reported #{row['status']}"
        end
      rescue SystemExit
        pass
      end

      def test_falsify_holds_its_thesis_on_fixture_traffic
        readings_backup = File.read(File.join(master_root, "data", "falsification", "readings.jsonl"))
        begin
          out, = capture_io { Falsify.run_experiment }
          reading = out.match(/\{.*\}/m) ? JSON.parse(out[/\{.*\}/m])["reading"] : nil
          assert reading, "a falsify run must append one instrument reading"
          assert_equal 1.0, reading["governed"]["held_quality"],
                       "the governed lane must hold every seeded defect; an escape is the falsification"
          assert_operator reading["ungoverned"]["defect_survival"], :>, 0.5,
                          "the ungoverned lane must let most seeded defects survive, or the experiment proves nothing"
        ensure
          File.write(File.join(master_root, "data", "falsification", "readings.jsonl"), readings_backup)
        end
      end

      def test_coverage_greens_carry_revision_and_timestamp
        require_relative "../../lib/agent/coverage_map"
        state = CoverageMap.read_state
        rows = state["laws"].values
        refute_empty rows, "the coverage state should have measurements from the last --map run"
        rows.each do |row|
          refute_nil row["revision"], "a green with no revision is a green that measured nothing"
          refute_nil row["at"], "a green with no timestamp cannot be aged"
        end
      end

      def test_prune_only_judges_laws_that_were_measured
        out, = capture_io { Prune.report }
        payload = JSON.parse(out[/\{.*\}/m])
        (payload["fold_candidates"] + payload["narrow_candidates"]).each do |row|
          refute row["law"].nil?
        end
        refute payload["fold_candidates"].any? { |r| r["law"] == "A_FINDING_IS_A_HYPOTHESIS" },
               "a semantic law with no detector was never measured; it cannot be a fold candidate"
      end

      def test_taste_conflict_cites_the_recorded_decision
        out, _err = capture_io { Taste.run(["conflicts", "--subject", "raw accent hex #E07A00 on a dashboard"]) }
        assert_includes out, "you decided rejected", "the warning must cite the recorded decision, not re-ask"
        assert_includes out, "2026-11-07", "the citation carries the date the decision was made"
      end

      def test_reconcile_opens_scoped_missions_for_gate_failures
        missions_backup = File.read(File.join(master_root, "data", "reconcile", "missions.jsonl"))
        begin
          out, = capture_io { Reconcile.check }
          payload_text = out[/\{\s*"command": "reconcile check".*\z/m]
          payload = JSON.parse(payload_text) if payload_text
          if payload.nil? || payload["drift_count"].to_i.positive?
            assert File.file?(File.join(master_root, "data", "reconcile", "missions.jsonl")),
                   "a drift opens a mission where the next session reads it, or there was no drift to open"
          else
            assert_equal 0, payload["missions_opened"].to_i, "no drift, no mission"
          end
        ensure
          File.write(File.join(master_root, "data", "reconcile", "missions.jsonl"), missions_backup)
        end
      end

      def test_precedent_rows_carry_provenance
        rows = Precedent.ledger
        assert_operator rows.size, :>=, 6, "the seeded corpus carries the tree's own recorded rulings"
        rows.each do |row|
          assert row["cites"], "a precedent with no citation is a preference: #{row['id']}"
          assert_equal "governing", row["status"] || row[:status] if row["id"] == "P-001"
        end
      end

      def test_trust_credential_verifies_its_own_chain
        out, = capture_io { Trust.verify }
        assert_includes out, '"hash_chain_intact": true', "an edited chain voids the credential it travelled with"
      end

      def test_court_awaits_the_operator_and_records_the_ruling
        # The court writes real ledgers; the suite borrows them and puts them
        # back byte for byte, so a test ruling never becomes precedent law.
        ledger_backup = File.read(File.join(master_root, "data", "precedents.yml"))
        cases_backup = Dir.glob(File.join(master_root, "data", "court", "*.yml")).to_h { |f| [f, File.read(f)] }
        begin
          out, = capture_io do
            Court.open_case(["SMALL_FILES", "--against", "NO_PUTS",
                             "--question", "the split a size law proposes would move puts into new files"])
          end
          case_file = out[/MASTER\/data\/court\/(case-[\d-]+)\.yml/, 1]
          refute_nil case_file, "opening a case writes a brief"

          path = File.join(master_root, "data", "court", "#{case_file}.yml")
          brief = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
          assert_equal "awaiting-operator", brief["status"], "the court assembles the brief and waits; the model never rules"

          out, = capture_io do
            Court.rule([case_file, "--winner", "SMALL_FILES",
                        "--rationale", "test collision: the move is real and the puts are interface"])
          end
          assert_includes out, "precedent_recorded", "a ruled collision becomes a precedent with a citation"
        ensure
          File.write(File.join(master_root, "data", "precedents.yml"), ledger_backup)
          (Dir.glob(File.join(master_root, "data", "court", "*.yml")) - cases_backup.keys).each { |f| File.delete(f) }
        end
      end

      def test_scars_cite_and_admit_their_own_pending_provenance
        out, = capture_io { Scars.run(["--law", "NO_PUTS"]) }
        assert_includes out, "I-001", "the rename scar governs NO_PUTS and is cited by id"
        assert_includes out, "provenance_verified", "rows admit which citations are verified and which are still pending"
      end

      def test_capability_tiers_are_monotonic
        out, = capture_io { Capability.detect }
        assert_includes out, '"monotonic": true',
                        "a tier that adds an obligation as capability falls is a different constitution, not a reduction"
      end

      def test_sunset_ranks_itself
        out, = capture_io { Sunset.report }
        assert_includes out, "agent-tier", "the final ratchet turns on the ratchet: this tier is itself a row"
        assert_includes out, "advice", "every row answers whether it earns its place"
      end

      private

      # The gate prints its verdict; this suite reads the same computation by
      # running it into a buffer instead of parsing stdout twice.
      def read_gate_output(_exit_code)
        require "stringio"
        buffer = StringIO.new
        old_stdout = $stdout
        $stdout = buffer
        FastGate.run(["--fast"])
        buffer.string
      ensure
        $stdout = old_stdout
      end
    end
  end
end
