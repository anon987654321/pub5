# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestScanOutput < Minitest::Test
  FakeRule = Struct.new(:id, :auto_fix)

  class FakeScanner
    attr_reader :rules, :scan_calls

    def initialize(findings_by_pass:, rules: [])
      @findings_by_pass = findings_by_pass
      @rules = rules
      @scan_calls = 0
    end

    def scan(_path, depth: :deep, **)
      @scan_calls += 1
      findings = @findings_by_pass.shift || []
      Master::Result.ok(findings)
    end

    def scan_dir(path, depth:, glob: "**/*", stream: false, **)
      @scan_calls += 1
      findings = @findings_by_pass.shift || []
      Master::Result.ok([[File.join(path, "example.rb"), Master::Result.ok(findings)]])
    end
  end

  def finding(rule, line: 1)
    {
      law: rule,
      message: "issue #{rule}",
      line:,
      severity: :info,
      fix: nil,
      tags: [],
      confidence: 0.9,
      why: "why",
      genealogy: %w[STYLE X],
      dedupe_key: "#{rule}:issue:#{line}",
    }
  end

  # One law and message in two files is one violation, and the line says how many findings it groups.
  def test_a_grouped_total_names_the_findings_behind_it
    pairs = %w[/tmp/a.rb /tmp/b.rb].map { |file| [file, Master::Result.ok([finding("LONG_LINE").except(:dedupe_key)])] }
    report = Master::CLI::Scan::Report.new(pairs:, profile: nil, rule_filter: nil)

    assert_match(/\A1 violations from 2 findings/, report.brief)
    assert_includes report.render, "1 total violations from 2 findings"
  end

  def test_scan_report_brief_and_delta
    pairs = [[
      "/tmp/a.rb",
      # Different lines so ConflictResolver does not collapse them
      Master::Result.ok([finding("LONG_LINE", line: 1), finding("DEAD_CODE", line: 2)]),
    ]]
    r1 = Master::CLI::Scan::Report.new(pairs:, profile: "full", rule_filter: nil, phase: "pass1")
    assert_match(/2 violations/, r1.brief)
    assert_match(/LONG_LINE|DEAD_CODE/, r1.brief)

    r2 = Master::CLI::Scan::Report.new(
      pairs: [[ "/tmp/a.rb", Master::Result.ok([finding("LONG_LINE", line: 1)]) ]],
      profile: "full",
      rule_filter: nil,
      phase: "pass2",
      prior_total: 2,
      autofixes: [{ path: "a.rb", transforms: [:frozen_string_literal] }],
    )
    text = r2.render
    assert_includes text, "phase: pass2"
    assert_includes text, "delta: 2 -> 1"
    assert_includes text, "autofixed: 1 file"
  end

  def test_scan_live_snapshot_written
    Dir.mktmpdir do |root|
      path = Master::CLI::Scan::Live.snapshot!("hello findings", root:, note: "test", announce: false)
      assert_equal File.join(root, ".master", "scan_last.txt"), path
      assert_includes File.read(path), "hello findings"
      assert_includes File.read(path), "test"
    end
  end

  def test_observe_emits_multiphase_and_snapshot
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "class Example\nend\n")
      scanner = FakeScanner.new(
        findings_by_pass: [[finding("FROZEN_LITERAL")], []],
        rules: [FakeRule.new("FROZEN_LITERAL", true)],
      )

      out = Master::CLI::CommandRegistry.observe(
        scanner:,
        root:,
        ctx: { args: path },
      )

      snap = File.join(root, ".master", "scan_last.txt")
      assert File.file?(snap), "expected final snapshot"
      assert_includes File.read(snap), "phase:"
      # Final render should mention phase and preferably autofix
      assert_match(/phase:|clean|violation|autofix/i, out)
    end
  end

  def test_help_documents_through_pass
    detail = Master::CLI::CommandRegistry.help_text("review")
    assert_includes detail, "critique"
  end

  # A hard slice cut mid-word and said nothing about it: an adversarial finding
  # ended "contradicting the commen", which reads as a typo in the finding
  # rather than the end of the room for it.
  def test_a_long_finding_is_cut_at_a_word_and_says_so
    report = Master::CLI::Scan::Report.allocate
    long = "adversarial: the MARKERS list holds words common in English, contradicting the comment above it"

    clipped = report.send(:clipped, long)

    assert_operator clipped.length, :<=, Master::VIOLATION_TRUNCATE + "...".length
    assert clipped.end_with?("..."), clipped
    assert_includes long.split, clipped.delete_suffix("...").split.last, "the cut landed mid-word"
    assert_equal long, report.send(:clipped, long, limit: 500)
  end

  # One unreadable file must not kill the whole observe phase, and must not be
  # dropped silently either: the report names the file and the reason, so a
  # partial scan can never render as a clean tree. data/self_findings.yml past
  # its line ceiling was the live crash: one RuntimeError took out every
  # whole-MASTER scan.
  def test_a_failed_read_is_named_unmeasured_instead_of_raising
    pairs = [
      ["/tmp/measured.rb", Master::Result.ok([finding("LONG_LINE", line: 1)])],
      ["/tmp/self_findings.yml", Master::Result.err("file too long: /tmp/self_findings.yml", category: :validation)],
    ]
    report = Master::CLI::Scan::Report.new(pairs:, profile: nil, rule_filter: nil)

    text = report.render
    assert_includes text, "1 total violations"
    assert_includes text, "unmeasured: /tmp/self_findings.yml (file too long"
    refute_includes text, "clean - no violations"
  end

  def test_an_unmeasured_file_keeps_a_zero_finding_scan_from_reading_as_clean
    pairs = [["/tmp/gone.rb", Master::Result.err("file too long: /tmp/gone.rb", category: :validation)]]
    report = Master::CLI::Scan::Report.new(pairs:, profile: nil, rule_filter: nil)

    text = report.render
    assert_includes text, "no violations in measured files; 1 unmeasured"
    assert_includes text, "unmeasured: /tmp/gone.rb"

    brief = report.brief
    assert_includes brief, "clean"
    assert_includes brief, "unmeasured 1 file"
  end

  def test_a_corpus_of_failed_reads_is_bounded_on_one_screen
    pairs = (1..7).map { |n| ["/tmp/f#{n}.rb", Master::Result.err("file too long: /tmp/f#{n}.rb", category: :validation)] }
    report = Master::CLI::Scan::Report.new(pairs:, profile: nil, rule_filter: nil)

    text = report.render
    assert_includes text, "unmeasured: 3 more files omitted"
    assert_equal 7, report.send(:failed_reads).size
  end
end
