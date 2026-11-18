# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../lib/operator/polish_lens"

class TestPolishLens < Minitest::Test
  def setup
    @root = Dir.mktmpdir("polish")
    FileUtils.mkdir_p("#{@root}/MASTER/lib")
    FileUtils.mkdir_p("#{@root}/MASTER/bin")
    FileUtils.mkdir_p("#{@root}/MASTER/test/fixtures/law/bad")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_keep_hygiene_flags_keep_in_populated_dir
    FileUtils.touch("#{@root}/MASTER/lib/.keep")
    FileUtils.touch("#{@root}/MASTER/lib/real.rb")
    assert_includes Operator::PolishLens.keep_hygiene(@root).map(&:id), "keep_hygiene"
  end

  def test_keep_hygiene_spares_empty_dir
    FileUtils.touch("#{@root}/MASTER/lib/.keep")
    assert_empty Operator::PolishLens.keep_hygiene(@root)
  end

  def test_exec_bit_flags_non_executable_bin
    File.write("#{@root}/MASTER/bin/tool", "#!/bin/sh\necho hi\n")
    FileUtils.chmod(0o644, "#{@root}/MASTER/bin/tool")
    assert_includes Operator::PolishLens.exec_bit(@root).map(&:id), "exec_bit"
  end

  def test_fixture_mirror_flags_missing_good
    FileUtils.touch("#{@root}/MASTER/test/fixtures/law/bad/x.rb")
    assert_includes Operator::PolishLens.fixture_mirror(@root).map(&:id), "fixture_mirror"
  end

  def test_shebang_portability_spares_openbsd_mirror
    FileUtils.mkdir_p("#{@root}/OPENBSD/mirror/usr/local/sbin")
    f = "#{@root}/OPENBSD/mirror/usr/local/sbin/admin"
    File.write(f, "#!/usr/local/bin/ruby\n")
    assert_empty Operator::PolishLens.shebang_portability(@root)
  end

  def test_shebang_portability_flags_absolute_ruby
    f = "#{@root}/MASTER/lib/tool.rb"
    File.write(f, "#!/usr/local/bin/ruby\n")
    assert_includes Operator::PolishLens.shebang_portability(@root).map(&:id), "shebang_portability"
  end

  def test_clean_tree_yields_no_findings
    FileUtils.touch("#{@root}/MASTER/lib/real.rb")
    FileUtils.mkdir_p("#{@root}/MASTER/test/fixtures/law/good")
    FileUtils.touch("#{@root}/MASTER/test/fixtures/law/bad/x.rb")
    FileUtils.touch("#{@root}/MASTER/test/fixtures/law/good/x.rb")
    assert_empty Operator::PolishLens.run(root: @root, json: true)
  end

  def test_candidates_carry_law_and_proof
    FileUtils.touch("#{@root}/MASTER/lib/.keep")
    FileUtils.touch("#{@root}/MASTER/lib/real.rb")
    f = Operator::PolishLens.keep_hygiene(@root)
    cand = Operator::PolishLens.to_candidates(f)["candidates"].first
    assert_equal "DENSITY", cand["law"]
    refute_nil cand["proof"]
    assert_equal "candidate", cand["status"]
  end

  def test_run_is_deterministic
    FileUtils.touch("#{@root}/MASTER/lib/.keep")
    FileUtils.touch("#{@root}/MASTER/lib/real.rb")
    a = Operator::PolishLens.run(root: @root, json: true).map(&:to_h)
    b = Operator::PolishLens.run(root: @root, json: true).map(&:to_h)
    assert_equal a, b
  end
end
