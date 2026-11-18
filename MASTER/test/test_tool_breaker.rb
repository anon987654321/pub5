# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "digest"
require_relative "../lib/fix/antigen_store"
require_relative "../lib/fix/repair_loop/outcome_tracking"
require_relative "../lib/trace/causal_trace"

# The failure this fuse closes: /fix re-asks the model about the same finding in
# the same unchanged file on every pass, and the answer has not changed. The
# counting stub below is that loop; without ToolBreaker it is asked every time.
class TestToolBreaker < Minitest::Test
  Rule = Struct.new(:id, :severity)
  Breaker = Master::Fix::ToolBreaker

  # A RepairLoop whose model call is a counter that always fails to propose.
  class CountingLoop < Master::Fix::RepairLoop
    attr_reader :asked

    def fix_violation(_violation)
      @asked = @asked.to_i + 1
      :no_proposal
    end
  end

  def setup
    Breaker.reset!
    @dir = Dir.mktmpdir("breaker")
    @path = File.join(@dir, "a.rb")
    File.write(@path, "x = 1\n")
    @violation = { file: @path, law: "TEST_RULE", message: "fix me", severity: :warning }
    @loop = CountingLoop.new(law: Rule.new("TEST_RULE", :warning), agent: Object.new, scanner: Object.new, root: Master::ROOT)
  end

  def teardown
    FileUtils.remove_entry(@dir)
    Breaker.reset!
  end

  def batch = @loop.send(:fix_batch, [@violation])

  def test_the_model_is_asked_three_times_for_an_unchanged_file_and_no_more
    out, = capture_io { 6.times { batch } }

    assert_equal 3, @loop.asked
    assert_equal 1, out.scan("fused on a.rb").size, "one dmesg line, at the moment it fuses"
    assert_equal 1, Breaker.fused_count
    assert_equal({ skip_fused: 1 }, @loop.instance_variable_get(:@batch_breakdown))
  end

  def test_a_changed_file_reopens_the_tuple
    capture_io { 3.times { batch } }
    File.write(@path, "x = 2\n")
    capture_io { batch }

    assert_equal 4, @loop.asked
    assert_equal 0, Breaker.fused_count
  end

  def test_a_different_finding_or_law_is_a_different_tuple
    capture_io { 3.times { batch } }

    assert Breaker.refuse?("TEST_RULE", @violation, Breaker.state_of(@violation))
    refute Breaker.refuse?("TEST_RULE", @violation.merge(message: "another"), Breaker.state_of(@violation))
    refute Breaker.refuse?("OTHER", @violation, Breaker.state_of(@violation))
  end

  def test_outages_and_applied_fixes_do_not_count
    state = Breaker.state_of(@violation)
    5.times { Breaker.record("TEST_RULE", @violation, state, :model_failed) }
    refute Breaker.refuse?("TEST_RULE", @violation, state)

    2.times { Breaker.record("TEST_RULE", @violation, state, :rejected) }
    Breaker.record("TEST_RULE", @violation, state, :applied)
    Breaker.record("TEST_RULE", @violation, state, :rejected)
    refute Breaker.refuse?("TEST_RULE", @violation, state)
  end

  def test_antigen_matches_only_the_same_source_revision
    store = Master::Fix::AntigenStore.new(root: @dir)
    digest = Digest::SHA256.file(@path).hexdigest
    id = store.record(
      law: "TEST_RULE", boundary: "a.rb", defect_class: "consensus_rejected",
      evidence: { source_sha256: digest, outcome: "consensus_rejected", prompt: "must never be stored" },
      note: "private reviewer note sk-abcdefghijklmnop",
    )

    assert_equal id, store.match(
      law: "TEST_RULE", boundary: "a.rb", defect_class: "consensus_rejected",
      source_sha256: digest, limit: 1,
    ).first.fetch("id")
    refute store.known?(
      law: "TEST_RULE", boundary: "a.rb", defect_class: "consensus_rejected",
      source_sha256: "0" * 64,
    )
    refute_includes File.read(File.join(@dir, Master::Fix::AntigenStore::DIR, Master::Fix::AntigenStore::FILE)),
                    "must never be stored"
    refute_includes File.read(File.join(@dir, Master::Fix::AntigenStore::DIR, Master::Fix::AntigenStore::FILE)),
                    "private reviewer note"
    refute_includes File.read(File.join(@dir, Master::Fix::AntigenStore::DIR, Master::Fix::AntigenStore::FILE)),
                    "sk-abcdefghijklmnop"
    antigen_path = File.join(@dir, Master::Fix::AntigenStore::DIR, Master::Fix::AntigenStore::FILE)
    assert_equal 0o600, File.stat(antigen_path).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(antigen_path)).mode & 0o777
  end

  def test_high_cost_law_budget_antigen_carries_run_bound_usage_receipts
    FileUtils.mkdir_p(File.join(@dir, ".master"))
    trace = Master::Trace::CausalTrace.start(run_id: "budget-run", root: @dir, agent: "fix")
    File.write(
      File.join(@dir, ".master", "costs.jsonl"),
      [
        { ts: 1, amount: 0.25, model: "priced-model", tokens: 200, run_id: "budget-run" },
        { ts: 2, amount: 0.03, model: "estimated-model", tokens: 40, run_id: "budget-run", approximate: true },
      ].map { |row| JSON.generate(row) }.join("\n") + "\n",
    )
    tracker = Object.new
    tracker.extend(Master::Fix::RepairLoop::OutcomeTracking)
    tracker.instance_variable_set(:@root, @dir)
    tracker.instance_variable_set(:@bus, nil)
    digest = Digest::SHA256.file(@path).hexdigest

    tracker.send(:record_budget_antigen, @violation, digest, 0.25, 200, law: "TEST_RULE")

    antigen = Master::Fix::AntigenStore.new(root: @dir).match(
      law: "TEST_RULE", boundary: "a.rb",
      defect_class: "high_cost_law_budget_exceeded", source_sha256: digest, limit: 1,
    ).first
    evidence = antigen.fetch("evidence")
    assert_equal "high_cost_law_budget_exceeded", evidence.fetch("outcome")
    assert_equal 0.25, evidence.fetch("cost_usd")
    assert_equal 200, evidence.fetch("cost_tokens")
    assert_equal "REPORTED_USAGE", evidence.fetch("usage_status")
    assert_equal 1, evidence.fetch("exact_receipts")
    assert_equal 1, evidence.fetch("estimated_records")
  ensure
    Master::Trace::CausalTrace.clear(trace) if defined?(trace)
  end
  def test_best_of_n_sees_a_fused_tuple
    ENV["MASTER_FIX_BEST_OF"] = "3"
    visual = @violation.merge(law: Master::Fix::BestOfN::LAW_ID, file: File.join(@dir, "a.scss"))
    File.write(visual[:file], ".a{}\n")
    assert Master::Fix::BestOfN.active?(visual, Object.new, tool: "LAW")
    state = Breaker.state_of(visual)
    capture_io { 3.times { Breaker.record("LAW", visual, state, :rejected) } }

    refute Master::Fix::BestOfN.active?(visual, Object.new, tool: "LAW")
  ensure
    ENV.delete("MASTER_FIX_BEST_OF")
  end

  def test_run_budget_reports_fused_tuples_at_the_pass_boundary
    said = []
    budget = Master::Fix::RunBudget.new(root: @dir, max_passes: 3, say: ->(text) { said << text }, poll_seconds: 0).start!
    budget.pass_end(1)
    refute said.any? { |line| line.include?("tuples fused") }

    state = Breaker.state_of(@violation)
    capture_io { 3.times { Breaker.record("TEST_RULE", @violation, state, :rejected) } }
    budget.pass_end(2)
    assert_includes said, "fix0: pass 2 1 tuples fused"
  end
end
