# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../detectors/declared_environment"
class DeclaredEnvironmentTest < Minitest::Test
  def test_finds_undeclared_environment_reads
    Dir.mktmpdir do |root|
      File.write(File.join(root, "bad.rb"), "ENV.fetch(\"UNDECLARED\")\n")
      File.write(File.join(root, "good.rb"), "Pub5::Core::Registry.load(\"registry/knobs.yml\")\n")
      assert_equal ["bad.rb"], Pub5::Laws::DeclaredEnvironment.findings(root).map(&:first)
    end
  end
end
