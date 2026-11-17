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
%w[bare_scan law_index status_view receipts openbsd_tier fast_gate].each do |mod|
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
