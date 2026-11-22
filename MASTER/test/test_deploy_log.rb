# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require_relative "../lib/operator/deploy_log"

class DeployLogTest < Minitest::Test
  Outcome = Struct.new(:url, :expires_in, :error, keyword_init: true) do
    def success? = !url.to_s.empty?
  end

  class FakePublisher
    attr_reader :calls

    def initialize
      @calls = []
    end

    def publish(**args)
      @calls << args
      Outcome.new(url: "https://pste.us/example", expires_in: "1 day")
    end
  end

  def test_local_log_is_private_and_keeps_all_lines_without_remote_file_paths
    Dir.mktmpdir do |dir|
      publisher = FakePublisher.new
      log = Operator::DeployLog.new(app: "all", sha: "a" * 40, directory: dir, publisher:)

      assert File.file?(log.path)
      assert_equal 0o600, File.stat(log.path).mode & 0o777
      assert_equal 0o700, File.stat(dir).mode & 0o777
      assert_match(%r{/deployments/|/tmp/}, log.path)
      refute_includes File.read(log.path), "/var/log/pub5"
    end
  end

  def test_snapshot_capture_appends_only_new_lines
    Dir.mktmpdir do |dir|
      log = Operator::DeployLog.new(app: "all", sha: "a" * 40, directory: dir, publisher: FakePublisher.new)
      first = log.append_snapshot("start\nstep one\n\n")
      second = log.append_snapshot("start\nstep one\nstep two\n\n")

      assert_equal "start\nstep one\n", first
      assert_equal "step two\n", second
      assert_equal 1, File.read(log.path).scan(/^step one$/).length
    end
  end

  def test_snapshot_capture_handles_tmux_history_scrolling_with_overlap
    Dir.mktmpdir do |dir|
      log = Operator::DeployLog.new(app: "all", sha: "a" * 40, directory: dir, publisher: FakePublisher.new)
      log.append_snapshot("line 1\nline 2\nline 3\n")
      appended = log.append_snapshot("line 2\nline 3\nline 4\n")

      assert_equal "line 4\n", appended
    end
  end

  def test_finish_publishes_a_redacted_operation_report_and_records_exit_status
    Dir.mktmpdir do |dir|
      publisher = FakePublisher.new
      log = Operator::DeployLog.new(app: "all", sha: "b" * 40, directory: dir, publisher:)
      log.append("deploy finished\n")
      outcome = log.finish(status: "success", exit_code: 0)

      assert outcome.success?
      assert_equal 0, Operator::DeployLog.read_status(log.path)
      assert_equal "deploy all", publisher.calls.fetch(0).fetch(:operation)
      assert_includes publisher.calls.fetch(0).fetch(:output), "deploy finished"
      assert_includes File.read(log.path), "https://pste.us/example"
    end
  end

  def test_existing_log_resume_rejects_symlinks_and_outside_paths
    Dir.mktmpdir do |dir|
      outside = File.join(dir, "outside.log")
      File.write(outside, "safe\n")
      File.symlink(outside, File.join(dir, "linked.log"))

      assert_raises(RuntimeError) do
        Operator::DeployLog.new(app: "all", sha: "a" * 40, directory: dir,
                                path: File.join(dir, "linked.log"), publisher: FakePublisher.new)
      end
    end
  end
end
