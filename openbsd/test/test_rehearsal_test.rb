# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require "digest"
require_relative "../lib/rehearsal"

class RehearsalTest < Minitest::Test
  def test_live_status_is_blocked_without_host_evidence
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "registry"))
      FileUtils.mkdir_p(File.join(root, "openbsd"))
      File.write(File.join(root, "registry", "hosts.yml"), { "hosts" => { "vm23" => { "required_observations" => %w[cpu disk restore_drill] } } }.to_yaml)
      File.write(File.join(root, "openbsd", "provenance.yml"), { "preserved_sources" => [] }.to_yaml)
      assert_equal ["BLOCKED", %w[cpu disk restore_drill]], OpenBSD::Rehearsal.new(root: root).live_status
    end
  end
end
