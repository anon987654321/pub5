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

  def test_private_index_and_history_findings_hide_subject_names_and_paths
    doctor = Studio::Doctor.new
    checks = []
    history = "STUDIO/lora/merethe/sources/01.jpg\nSTUDIO/lora/ragnhild/subject.env\n"
    status = Struct.new(:success?).new(true)

    Studio::Subprocess.stub(:capture3, ->(*arguments, timeout:) {
      if arguments.include?("ls-files")
        assert_equal 10, timeout
        ["", "", status]
      elsif arguments.include?("rev-parse")
        assert_equal 10, timeout
        ["false", "", status]
      else
        assert_includes arguments, "--all"
        assert_includes arguments, ":(glob)STUDIO/lora/*/sources/**"
        assert_equal 45, timeout
        [history, "", status]
      end
    }) do
      doctor.send(:private_media_check, checks)
    end

    index_check = checks.find { |check| check.fetch("id") == "private_subject_index" }
    history_check = checks.find { |check| check.fetch("id") == "private_subject_history" }
    assert_equal "PASS", index_check.fetch("state")
    assert_equal "BLOCKED", history_check.fetch("state")
    assert_includes history_check.fetch("detail"), "2 subject-private path(s)"
    serialized = JSON.generate(checks)
    refute_includes serialized, "merethe"
    refute_includes serialized, "ragnhild"
    refute_includes serialized, "sources/01.jpg"
    refute_includes serialized, "subject.env"
  end

  def test_shallow_checkout_does_not_report_private_history_clean
    doctor = Studio::Doctor.new
    checks = []
    status = Struct.new(:success?).new(true)

    Studio::Subprocess.stub(:capture3, ->(*arguments, timeout:) {
      if arguments.include?("ls-files")
        ["", "", status]
      elsif arguments.include?("rev-parse")
        ["true", "", status]
      else
        flunk "a shallow checkout must not run a partial history scan"
      end
    }) do
      doctor.send(:private_media_check, checks)
    end

    history_check = checks.find { |check| check.fetch("id") == "private_subject_history" }
    assert_equal "INCONCLUSIVE", history_check.fetch("state")
    assert_includes history_check.fetch("detail"), "repository is shallow"
  end
end
