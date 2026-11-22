# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../../lib/operator/polish_lens"
require_relative "../../lib/operator/polish_apply"

class TestPolishApply < Minitest::Test
  def setup
    @root = Dir.mktmpdir("polishapply")
    FileUtils.mkdir_p("#{@root}/MASTER/lib")
    FileUtils.mkdir_p("#{@root}/MASTER/bin")
    FileUtils.mkdir_p("#{@root}/MASTER/data")
    File.write("#{@root}/MASTER/data/soul.yml", YAML.dump("absolute" => { "sacred_paths" => ["MASTER/data/soul.yml"] }))
    FileUtils.touch("#{@root}/MASTER/lib/.keep")
    FileUtils.touch("#{@root}/MASTER/lib/real.rb")
    File.write("#{@root}/MASTER/bin/tool", "#!/bin/sh\necho\n")
    FileUtils.chmod(0o644, "#{@root}/MASTER/bin/tool")
    File.write("#{@root}/MASTER/lib/abs.rb", "#!/usr/local/bin/ruby\nputs 1\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_dry_run_writes_nothing
    Operator::PolishLens.apply(root: @root, dry_run: true)
    assert File.exist?("#{@root}/MASTER/lib/.keep")
    refute File.executable?("#{@root}/MASTER/bin/tool")
    assert File.read("#{@root}/MASTER/lib/abs.rb").start_with?("#!/usr/local/bin/ruby")
  end

  def test_apply_fixes_mechanical_subset
    Operator::PolishLens.apply(root: @root, dry_run: false)
    refute File.exist?("#{@root}/MASTER/lib/.keep")
    assert File.executable?("#{@root}/MASTER/bin/tool")
    assert File.read("#{@root}/MASTER/lib/abs.rb").start_with?("#!/usr/bin/env ruby")
    refute_empty Dir["#{@root}/.master/polish/receipts/*.yml"]
  end

  def test_sacred_path_is_refused
    assert Operator::PolishLens.sacred?(@root, "MASTER/data/soul.yml")
  end

  def test_antigen_is_consulted
    f = Operator::PolishLens.collect(@root).find { |x| x.id == "keep_hygiene" }
    Operator::PolishLens.remember_antigen(@root, f, "test")
    Operator::PolishLens.apply(root: @root, dry_run: false)
    assert File.exist?("#{@root}/MASTER/lib/.keep"), "antigen-protected finding must not be applied"
  end

  def test_clean_tree_applies_nothing
    FileUtils.rm_f("#{@root}/MASTER/lib/.keep")
    FileUtils.rm_f("#{@root}/MASTER/lib/abs.rb")
    FileUtils.chmod(0o755, "#{@root}/MASTER/bin/tool")
    assert_empty Operator::PolishLens.collect(@root)
  end
end
