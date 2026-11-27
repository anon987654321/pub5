# frozen_string_literal: true

require_relative "test_helper"
require "operator/parse_sweep"
require "tmpdir"
require "open3"

class TestParseSweep < Minitest::Test
  # A string literal followed on the next line by another with no comma between
  # them is a syntax error that stops MASTER booting.
  MISSING_COMMA = <<~RUBY
    HELP = [
      "/chat quit - disconnect."
      "/chat summarize - ask the model.",
    ].freeze
  RUBY

  def repo(files)
    Dir.mktmpdir("parse-sweep") do |dir|
      Open3.capture2e("git", "init", "-q", dir)
      files.each { |name, body| File.write(File.join(dir, name), body) }
      Open3.capture2e("git", "-C", dir, "add", ".")
      yield dir
    end
  end

  def test_a_missing_comma_is_reported_with_its_file_and_line
    repo("ok.rb" => "puts 1\n", "chat.rb" => MISSING_COMMA) do |dir|
      broken = Operator::ParseSweep.failures(dir)
      assert_equal ["chat.rb"], broken.map(&:path)
      assert_equal 3, broken.first.line
    end
  end

  def test_a_clean_tree_reports_nothing
    repo("ok.rb" => "puts 1\n") { |dir| assert_empty Operator::ParseSweep.failures(dir) }
  end

  def test_a_tracked_file_deleted_from_disk_is_skipped
    repo("gone.rb" => "puts 1\n") do |dir|
      File.delete(File.join(dir, "gone.rb"))
      assert_empty Operator::ParseSweep.failures(dir)
    end
  end

  def test_target_scope_keeps_runtime_and_rails_dependencies
    paths = %w[MASTER/lib/boot.rb RAILS/brgen/app.rb RAILS/__shared/helper.rb RAILS/amber/app.rb STUDIO/music.rb]
    Operator::ParseSweep.stub(:tracked, paths) do
      assert_equal paths.first(4), Operator::ParseSweep.paths_for("/repo", "RAILS/brgen")
      assert_equal paths.first(4), Operator::ParseSweep.paths_for("/repo", "RAILS")
      assert_equal paths, Operator::ParseSweep.paths_for("/repo", ".")
    end
  end

  def test_the_repository_itself_parses
    root = File.expand_path("../..", __dir__)
    assert_empty Operator::ParseSweep.failures(root), "tracked Ruby that does not parse"
  end

  # Ruby before 3.3 has no Prism; the sweep must still answer, with the same
  # file and line, instead of dying on the require.
  def test_the_interpreter_fallback_reports_the_same_file_and_line
    Dir.mktmpdir("parse-sweep") do |dir|
      path = File.join(dir, "chat.rb")
      File.write(path, MISSING_COMMA)
      line, message = Operator::ParseSweep.parse_error_without_prism(path)
      assert_equal 3, line
      refute_empty message
      File.write(path, "puts 1\n")
      assert_nil Operator::ParseSweep.parse_error_without_prism(path)
    end
  end
end
