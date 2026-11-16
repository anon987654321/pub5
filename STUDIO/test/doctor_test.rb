# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../doctor"

class TestStudioDoctor < Minitest::Test
  def test_ruby_floor_is_numeric_not_lexical
    assert Studio::Doctor.ruby_supported?("3.3.0")
    assert Studio::Doctor.ruby_supported?("4.0.5")
    refute Studio::Doctor.ruby_supported?("3.2.99")
    refute Studio::Doctor.ruby_supported?("not-a-version")
  end

  def test_only_fail_and_blocked_states_make_a_report_not_ready
    refute Studio::Doctor.ready?([{ "state" => "BLOCKED" }])
    refute Studio::Doctor.ready?([{ "state" => "FAIL" }])
    assert Studio::Doctor.ready?([{ "state" => "PASS" }, { "state" => "OPTIONAL_MISSING" }])
    assert Studio::Doctor.ready?([{ "state" => "INCONCLUSIVE" }])
  end

  def test_report_is_explicitly_read_only_and_never_calls_a_provider
    report = Studio::Doctor.new.report

    assert_equal "studio.doctor.v1", report.fetch("schema")
    assert_equal true, report.fetch("read_only")
    assert_equal 0, report.fetch("provider_calls")
    assert report.fetch("checks").all? { |check| check.keys.sort == %w[detail id state] }
  end

  def test_private_subject_finding_never_prints_the_subject_or_path
    doctor = Studio::Doctor.new
    checks = []
    doctor.send(:add, checks, "private_subject_history", "BLOCKED",
                "3 subject-private path(s) are tracked; operator review is required")

    serialized = JSON.generate(checks)
    refute_match(/merethe|ragnhild|johann|sources\\/|consent\\.yml/, serialized)
  end
end
