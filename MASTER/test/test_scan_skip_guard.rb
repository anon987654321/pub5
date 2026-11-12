# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/scan_skip_guard"
require_relative "../lib/fix/scan/file_processor"

# A scan that could not measure its files must not report them clean.
class TestScanSkipGuard < Minitest::Test
  Guard = Master::Fix::ScanSkipGuard
  Failure = Struct.new(:category, :message)

  NAME_ERROR = "scan failed: NameError: uninitialized constant Master::Fix::Scan::FileProcessor::Operator at lib/x.rb:1"

  # The refusal a lane says while it cools off, wrapped the way ScanPhase.call
  # wraps any scan crash. The OPENBSD run of 2026-11-09 skipped 5 of 225 files
  # on exactly this and died.
  LANE_ERROR = "fix scan failed for lib/x.rb: RuntimeError: no gateway answer in 3 calls in a row; " \
               "gateway is skipped for 5 minutes. /model list says what each lane needs."

  def failure(message = NAME_ERROR, category: :infrastructure) = Failure.new(category, message)

  def test_one_exception_class_across_many_files_aborts
    guard = Guard.new
    21.times { |i| guard.record("f#{i}.rb", failure) }

    error = assert_raises(Master::Fix::MassSkipError) { guard.check!(total: 100_000) }
    assert_equal "NameError", error.signature
    assert_equal 21, error.count
  end

  def test_two_percent_of_files_aborts_even_when_the_causes_differ
    guard = Guard.new
    5.times { |i| guard.record("f#{i}.rb", failure("scan failed: Errno::EIO: x#{i}")) }

    assert_raises(Master::Fix::MassSkipError) { guard.check!(total: 100) }
  end

  def test_a_few_skips_in_a_large_run_pass
    guard = Guard.new
    3.times { |i| guard.record("f#{i}.rb", failure) }

    guard.check!(total: 1000)
  end

  def test_refusals_of_single_files_are_not_counted
    guard = Guard.new
    50.times { |i| guard.record("f#{i}.rb", failure("file too long: f", category: :validation)) }

    assert_equal 0, guard.size
    guard.check!(total: 50)
  end

  def test_signature_without_a_class_groups_by_message_not_path
    a = Guard.signature("scan failed: boom at /a/b.rb:3")
    b = Guard.signature("scan failed: boom at /c/d.rb:9")
    assert_equal a, b
  end

  def test_pass_runner_aborts_instead_of_counting_the_scan_clean_and_uses_the_real_total
    runner = Master::Fix::FixLoop::PassRunner.allocate
    scan_phase = Object.new
    scan_phase.define_singleton_method(:call) { |_path| Master::Result.err(NAME_ERROR, category: :infrastructure) }
    preflight = Object.new
    preflight.define_singleton_method(:findings) { |_paths| [] }
    runner.instance_variable_set(:@root, Dir.pwd)
    runner.instance_variable_set(:@scan_phase, scan_phase)
    runner.instance_variable_set(:@preflight, preflight)
    runner.instance_variable_set(:@skip_guard, Guard.new)
    paths = Array.new(30) { |i| "tmp-skip-#{i}" }
    File.stub(:exist?, true) do
      error = assert_raises(Master::Fix::MassSkipError) { runner.violations(paths) }
      assert_equal 30, error.total
      assert_match(/\d+ of 30 file\(s\) skipped/, error.message)
    end
  end

  # A mass skip of lane cool-off refusals is retryable: the pass waits out the
  # silence and rescans once instead of dying to an outage that recovers alone.
  def test_lane_cooloff_mass_skip_raises_the_retryable_error
    guard = Guard.new
    5.times { |i| guard.record("f#{i}.rb", failure(LANE_ERROR)) }

    error = assert_raises(Master::Fix::LaneCooloffSkipError) { guard.check!(total: 225) }
    assert_kind_of Master::Fix::MassSkipError, error
    assert_equal 5, error.count
    assert_equal 225, error.total
  end

  # A genuine code failure stays fatal even when one lane refusal is mixed in.
  def test_a_lane_refusal_minority_does_not_downgrade_the_abort
    guard = Guard.new
    5.times { |i| guard.record("e#{i}.rb", failure("scan failed: Errno::EIO: x#{i}")) }
    guard.record("l0.rb", failure(LANE_ERROR))

    error = assert_raises(Master::Fix::MassSkipError) { guard.check!(total: 250) }
    refute_kind_of Master::Fix::LaneCooloffSkipError, error
  end

  def test_pass_runner_waits_out_a_lane_cooloff_and_rescans_once
    runner = Master::Fix::FixLoop::PassRunner.allocate
    calls = 0
    scan_phase = Object.new
    scan_phase.define_singleton_method(:call) do |_path|
      calls += 1
      Master::Result.err(LANE_ERROR, category: :infrastructure)
    end
    preflight = Object.new
    preflight.define_singleton_method(:findings) { |_paths| [] }
    runner.instance_variable_set(:@root, Dir.pwd)
    runner.instance_variable_set(:@scan_phase, scan_phase)
    runner.instance_variable_set(:@preflight, preflight)
    runner.instance_variable_set(:@skip_guard, Guard.new)
    paths = Array.new(30) { |i| "tmp-cooloff-#{i}" }
    File.stub(:exist?, true) do
      Master::Io::LaneSilence.stub(:silent?, false) do
        # The lane answers "not silent", so the wait ends at once; the rescan
        # still runs (five more scan calls) before the second abort.
        error = assert_raises(Master::Fix::LaneCooloffSkipError) { runner.violations(paths) }
        assert_equal 30, error.total
      end
    end
    assert_equal 6, calls, "the pass must rescan once after the cool-off (3 + 3 scan calls: MIN_SKIPS trips first)"
  end

  def test_expected_semantic_inconclusive_keeps_mechanical_findings
    processor = Master::Fix::Scan::FileProcessor.new
    mechanical = Object.new
    mechanical.define_singleton_method(:id) { "TEST_MECHANICAL" }
    mechanical.define_singleton_method(:check) do |_code, path:|
      [{ law: "TEST_MECHANICAL", severity: :warning, line: 1, message: "mechanical finding" }]
    end
    semantic = Object.new
    semantic.define_singleton_method(:id) { "semantic" }
    semantic.define_singleton_method(:check) do |_code, path:|
      raise Master::Review::Scan::Detector::SemanticAssessmentInconclusive,
            "semantic assessment INCONCLUSIVE: provider spend/quota limit reached for #{path}"
    end

    findings = processor.send(
      :apply_laws,
      code: "value = 1\n",
      ast: nil,
      path: "tmp/inconclusive.rb",
      law_set: [mechanical, semantic],
    )

    assert_equal ["TEST_MECHANICAL"], findings.map { |finding| finding[:law] }
    assert_equal 1, processor.semantic_gaps.size
    assert_match(/provider spend\/quota limit reached/, processor.semantic_gaps.values.first)
  end
  def test_untyped_runtime_error_with_the_same_message_is_not_swallowed
    processor = Master::Fix::Scan::FileProcessor.new
    semantic = Object.new
    semantic.define_singleton_method(:id) { "semantic" }
    semantic.define_singleton_method(:check) do |_code, path:|
      raise "semantic assessment INCONCLUSIVE: unrelated runtime fault for #{path}"
    end

    error = assert_raises(RuntimeError) do
      processor.send(
        :apply_laws,
        code: "value = 1\n",
        ast: nil,
        path: "tmp/runtime_fault.rb",
        law_set: [semantic],
      )
    end

    assert_match(/unrelated runtime fault/, error.message)
    assert_empty processor.semantic_gaps
  end
end
