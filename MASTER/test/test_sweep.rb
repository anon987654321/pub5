# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/sweep"

# The instruments existed and had no shared vocabulary: eight tools, eight
# ceiling files, eight invocations, and `MASTER/bin/operator measure` aggregating the
# numbers but not the questions. This runs them as one pass per tree and reports
# in the dmesg form Trace::Dmesg and Pipeline::Pass already use.
class TestSweep < Minitest::Test
  S = Operator::Sweep

  def test_every_probe_names_a_real_tree
    unknown = S.probes.flat_map(&:trees).uniq - S::TREES

    assert_empty unknown
  end

  def test_every_probe_is_runnable
    S.probes.each do |probe|
      assert_respond_to probe.run, :call, "#{probe.unit} has no runner"
      arity = probe.scoped ? 1 : 0
      assert_equal arity, probe.run.arity, "#{probe.unit} scoped=#{probe.scoped.inspect} but takes #{probe.run.arity}"
    end
  end

  def test_probe_units_are_unique
    units = S.probes.map(&:unit)

    assert_equal units.uniq, units
  end

  # The bug this caught on its first honest run: design_baseline prints its
  # summary BEFORE its per-app detail, so "the last line is the verdict" reported
  # "shared: 1" as the verdict and hid "1 violation(s) (ceiling 0)" behind it.
  def test_the_verdict_is_the_summary_line_not_the_last_line
    body = ["design_baseline: 1 violation(s) (ceiling 0)", "  shared: 1 (ceiling -)"]

    assert_equal "1 violation(s) (ceiling 0)", S.verdict(body)
  end

  def test_the_verdict_falls_back_to_the_last_line
    assert_equal "no summary here", S.verdict(["  detail", "no summary here"])
  end

  def test_repo_ecology_is_registered_per_tree_and_marks_history_unmeasured
    probe = S.probes.find { |row| row.unit == "repoecology" }

    refute_nil probe
    assert probe.scoped
    assert_equal S::TREES, probe.trees
  end

  def test_full_sprawl_census_is_a_single_read_only_master_probe
    probe = S.probes.find { |row| row.unit == "sprawl" }

    refute_nil probe
    refute probe.scoped
    assert_equal %w[MASTER], probe.trees
    assert_equal 1, S.probes.count { |row| row.unit == "sprawl" }
  end

  def test_detailed_sweep_reports_process_execution_without_claiming_a_law_pass
    probe = S::Probe.new(unit: "fixture", trees: %w[MASTER], run: -> { [true, ["fixture: 2 findings above ceiling"]] })
    results = nil

    S.stub(:probes, [probe]) do
      S.stub(:tree_summary, "fixture tree") do
        Master::Trace::Dmesg.stub(:attach, nil) do
          Master::Trace::Dmesg.stub(:status, nil) do
            results = S.sweep("MASTER", 7, detailed: true)
          end
        end
      end
    end

    assert_equal 1, results.size
    result = results.first
    assert_equal "MASTER", result.tree
    assert_equal "fixture7", result.unit
    assert result.executed
    assert result.process_success
    assert_equal "2 findings above ceiling", result.summary
    assert_empty result.evidence
    refute_equal "PASS", result.process_success.to_s.upcase,
                 "process exit success is not a Law verdict"
  end

  def test_detailed_sweep_records_probe_failures_and_continues
    first = S::Probe.new(unit: "broken", trees: %w[MASTER], run: -> { [false, ["broken: failed", "detail one"]] })
    second = S::Probe.new(unit: "next", trees: %w[MASTER], run: -> { [true, ["next: completed"]] })
    results = nil

    S.stub(:probes, [first, second]) do
      S.stub(:tree_summary, "fixture tree") do
        Master::Trace::Dmesg.stub(:attach, nil) do
          Master::Trace::Dmesg.stub(:status, nil) do
            results = S.sweep("MASTER", 0, detailed: true)
          end
        end
      end
    end

    assert_equal [false, true], results.map(&:process_success)
    assert_equal ["detail one"], results.first.evidence
    assert_equal "completed", results.last.summary
  end

  def test_detailed_sweep_honours_cancellation_before_the_next_probe
    called = []
    probe = S::Probe.new(unit: "stopped", trees: %w[MASTER], run: -> { called << true; [true, ["stopped: done"]] })
    results = nil

    S.stub(:probes, [probe]) do
      S.stub(:tree_summary, "fixture tree") do
        Master::Trace::Dmesg.stub(:attach, nil) do
          results = S.sweep("MASTER", 0, detailed: true, stop: -> { true })
        end
      end
    end

    assert_empty called
    refute results.first.executed
    assert_nil results.first.process_success
    assert_match(/cancelled/, results.first.summary)
  end

  def test_legacy_sweep_return_shape_is_unchanged
    probe = S::Probe.new(unit: "fixture", trees: %w[MASTER], run: -> { [true, ["fixture: ok"]] })
    result = nil

    S.stub(:probes, [probe]) do
      S.stub(:tree_summary, "fixture tree") do
        Master::Trace::Dmesg.stub(:attach, nil) do
          result = S.sweep("MASTER", 3)
        end
      end
    end

    assert_equal [["fixture", 3]], result
  end

  # A census reported repo-wide under four tree headings is one fact wearing four
  # names. Scoped probes take the tree; unscoped ones say so by not taking it.
  def test_the_cohesion_probe_is_scoped
    assert S.probes.find { |p| p.unit == "cohesion" }.scoped
  end

  def test_repo_wide_probes_are_claimed_by_one_tree_only
    S.probes.reject(&:scoped).each do |probe|
      assert_equal 1, probe.trees.size,
                   "#{probe.unit} is unscoped, so listing it under #{probe.trees.size} trees prints the same number twice"
    end
  end

  # OPENBSD and STUDIO had one probe each against MASTER's eleven, so their
  # headings reported a repo-wide cohesion number and nothing else — a sweep
  # that measures almost nothing still prints a clean-looking block.
  def test_every_tree_has_a_probe_of_its_own
    S::TREES.each do |tree|
      own = S.probes.select { |p| p.trees == [tree] }

      refute_empty own, "#{tree} has no probe that speaks only for it"
    end
  end

  def test_sibling_probes_point_at_a_script_that_exists
    # OPENBSD's obsdreach probe runs bin/reach: the module moved to lib/reach.rb
    # when OPENBSD/tools/ was deleted (6e09c6919), because require cannot load an
    # extensionless file, and bin/reach stayed as the executable shim the probe
    # names. STUDIO's check moved the other way, from a check.rb script into
    # `rake check`, so its probe follows the Rakefile now. BIZ's instrument
    # moved inside its own tree on 2026-11-08: BIZ/tools/bp_check.mjs, beside
    # the plan folders it reads.
    {
      "OPENBSD" => "bin/reach",
      "STUDIO" => "Rakefile",
      "BIZ" => nil
    }.each do |tree, script|
      next if script.nil?

      path = File.join(S::ROOT, tree, script)

      assert File.file?(path), "#{tree} probe runs #{script}, which is not there"
    end

    assert File.file?(File.join(S::ROOT, "BIZ", "tools", "bp_check.mjs")),
           "BIZ probe runs bp_check.mjs, which is not there"
  end

  def test_the_ledger_parses_and_every_row_is_shaped
    rows = S.ledger.fetch("proposals")

    refute_empty rows
    rows.each do |row|
      assert_includes %w[open landed refuted], row["state"], "#{row['id']} has state #{row['state'].inspect}"
      assert_includes S::TREES, row["tree"], "#{row['id']} names tree #{row['tree'].inspect}"
      refute_nil row["claim"], "#{row['id']} has no claim"
    end
  end

  # The point of the file. A loop that cannot say "tried it, wrong, here is why"
  # proposes the same thing every round and never plateaus.
  def test_every_refuted_row_carries_its_reason
    S.ledger.fetch("proposals").select { |r| r["state"] == "refuted" }.each do |row|
      refute_nil row["reason"], "#{row['id']} is refuted with no reason - the next round will re-propose it"
      refute_nil row["refuted_by"], "#{row['id']} names nothing that would catch it again"
    end
  end

  # A proposal can close over several commits — lib/ground took four, three
  # regroups and a refutation — so this reads a list and requires every entry to
  # be a real sha rather than assuming one closes one.
  def test_every_landed_row_names_its_commits
    S.ledger.fetch("proposals").select { |r| r["state"] == "landed" }.each do |row|
      shas = row["landed_by"].to_s.split

      refute_empty shas, "#{row['id']} landed without a commit"
      shas.each { |sha| assert_match(/\A[0-9a-f]{7,40}\z/, sha, "#{row['id']} names #{sha.inspect}") }
    end
  end

  def test_proposal_ids_are_unique
    ids = S.ledger.fetch("proposals").map { |r| r["id"] }

    assert_equal ids.uniq, ids
  end
end
