# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require_relative "../doctor"

class TestStudioDoctor < Minitest::Test
  def test_ruby_floor_is_numeric_not_lexical
    assert Studio::Doctor.ruby_supported?("3.2.0")
    assert Studio::Doctor.ruby_supported?("3.2.99")
    assert Studio::Doctor.ruby_supported?("3.3.0")
    assert Studio::Doctor.ruby_supported?("4.0.5")
    refute Studio::Doctor.ruby_supported?("3.1.99")
    refute Studio::Doctor.ruby_supported?("not-a-version")
  end

  def test_only_fail_and_blocked_states_make_a_report_not_ready
    refute Studio::Doctor.ready?([{ "state" => "BLOCKED" }])
    refute Studio::Doctor.ready?([{ "state" => "FAIL" }])
    assert Studio::Doctor.ready?([{ "state" => "PASS" }, { "state" => "OPTIONAL_MISSING" }])
    refute Studio::Doctor.ready?([{ "state" => "INCONCLUSIVE" }])
  end

  def test_studio_root_contains_exactly_the_four_declared_owners
    Dir.mktmpdir do |root|
      Studio::Doctor::ROOT_OWNERS.each { |owner| Dir.mkdir(File.join(root, owner)) }

      valid, detail = Studio::Doctor.root_layout(root)
      assert valid
      assert_includes detail, "Exactly four real owners"

      File.write(File.join(root, "stray.txt"), "no")
      valid, detail = Studio::Doctor.root_layout(root)
      refute valid
      assert_includes detail, "stray.txt"
    end
  end

  def test_report_is_explicitly_read_only_and_never_calls_a_provider
    report = Studio::Doctor.new.report

    assert_equal "studio.doctor.v1", report.fetch("schema")
    assert_equal true, report.fetch("read_only")
    assert_equal 0, report.fetch("provider_calls")
    assert report.fetch("checks").all? { |check| check.keys.sort == %w[detail id state] }
  end

  def test_missing_provider_credential_is_inconclusive_and_not_ready
    checks = []
    doctor = Studio::Doctor.new

    Studio::ReplicateClient.stub(:load_token, "") do
      doctor.send(:provider_credential_check, checks, paths: [])
    end

    check = checks.fetch(0)
    assert_equal "provider_credentials", check.fetch("id")
    assert_equal "INCONCLUSIVE", check.fetch("state")
    refute Studio::Doctor.ready?(checks)
    refute_includes check.fetch("detail"), "token"
  end

  def test_world_readable_provider_token_file_fails_closed
    Dir.mktmpdir do |directory|
      token_path = File.join(directory, "config.json")
      File.write(token_path, '{"api_token":"not-a-real-token"}')
      File.chmod(0o644, token_path)
      checks = []

      Studio::ReplicateClient.stub(:load_token, "") do
        Studio::Doctor.new.send(:provider_credential_check, checks, paths: [token_path])
      end

      check = checks.fetch(0)
      assert_equal "provider_credentials", check.fetch("id")
      assert_equal "FAIL", check.fetch("state")
      refute_includes check.fetch("detail"), token_path
      refute Studio::Doctor.ready?(checks)
    end
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

  def test_loose_subject_photographs_are_private_even_outside_sources
    doctor = Studio::Doctor.new

    assert doctor.send(:private_path?, "STUDIO/lora/johann/portrait.jpg")
    assert doctor.send(:private_path?, "STUDIO/lora/ragnhild/contact-sheet.png")
    assert doctor.send(:private_path?, "STUDIO/lora/merethe/model.safetensors")
    refute doctor.send(:private_path?, "STUDIO/lora/ragnhild/train.yaml")
    assert_includes Studio::Doctor::PRIVATE_PATHSPECS, ":(glob)STUDIO/lora/**/*.jpg"
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
