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
    refute Studio::Doctor.ready?([{ "state" => "INCONCLUSIVE" }])
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
    tracked = "STUDIO/lora/merethe/sources/01.jpg\0STUDIO/lora/ragnhild/subject.env\0"
    status = Struct.new(:success?).new(true)

    Studio::Subprocess.stub(:capture3, ->(*_arguments, timeout:) {
      assert_equal 10, timeout
      [tracked, "", status]
    }) do
      doctor.send(:private_media_check, checks)
    end

    assert_equal "BLOCKED", checks.fetch(0).fetch("state")
    assert_includes checks.fetch(0).fetch("detail"), "2 subject-private path(s)"
    serialized = JSON.generate(checks)
    refute_includes serialized, "merethe"
    refute_includes serialized, "ragnhild"
    refute_includes serialized, "sources/01.jpg"
    refute_includes serialized, "subject.env"
  end
end
