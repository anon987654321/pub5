# frozen_string_literal: true

require_relative "test_helper"

class TestPrivacyAuditor < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("privacy-auditor")
    @auditor = Master::Ground::PrivacyAuditor.new(root: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  def test_counts_and_redacts_personal_data
    result = @auditor.scan(text: "Contact jane@example.test or 555-123-4567", source: "fixture")
    assert result.ok?
    data = result.value!
    assert_equal 1, data[:pii][:email]
    assert_equal 1, data[:pii][:phone]
    refute_includes data[:samples].join, "jane@example.test"
    assert_includes data[:samples].join, "[REDACTED]"
  end

  def test_social_security_pattern_is_high_risk
    result = @auditor.scan(text: "SSN 123-45-6789")
    assert_equal "HIGH", result.value![:risk]
  end

  def test_sample_limit_is_enforced
    result = @auditor.scan(text: (1..8).map { |i| "person#{i}@example.test" }.join("\n"), max_sample: 2)
    assert_equal 2, result.value![:samples].size
    assert @auditor.scan(text: "hello", max_sample: 6).err?
  end

  def test_refuses_secret_paths_and_paths_outside_root
    File.write(File.join(@dir, ".env"), "TOKEN=value")
    assert_equal :policy, @auditor.scan_file(path: ".env").category
    Dir.mktmpdir("outside") do |outside|
      assert_equal :policy, @auditor.scan_file(path: File.join(outside, "data.txt")).category
    end
  end

  def test_refuses_symlinked_file
    File.write(File.join(@dir, "data.txt"), "jane@example.test")
    File.symlink(File.join(@dir, "data.txt"), File.join(@dir, "linked.txt"))
    assert_equal :policy, @auditor.scan_file(path: "linked.txt").category
  end
end
