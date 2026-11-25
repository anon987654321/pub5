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

  FAILED_TRANSCRIPT = <<~LOG.freeze
    log: /home/op/.pub5/deployments/deploy-x.log
    vps-deploy: all -> master

    2026-11-25T13:24:38Z host=brgen pid=1 app=all stage=all:master enter
    2026-11-25T13:24:43Z host=brgen pid=2 app=master stage=master enter
    Cannot write a changed lockfile while frozen.
    checks0 at rails: 1 pass, 0 fail, 0 skip, 0 error in 0.2s
    probe_http: FAIL http://127.0.0.1:53187
      - authed metrics 401

    <!DOCTYPE html><html></html>tts_socket false: nil
    tts_socket false: nil
    stamp0: /var/db/pub5/last_deploy_master.json
    vps-deploy: master FAILED at stage "master" (exit 1)
    vps-deploy: brgen is DOWN (shed or stopped)
    2026-11-25T13:27:50Z host=brgen pid=2 app=master stage=master finished exit=1
    vps-deploy: all FAILED at stage "all:master" (exit 1)
    PUB5_DEPLOY_EXIT=1
  LOG

  def test_failure_digest_names_the_inner_stage_its_causes_and_the_transcript
    digest = Operator::DeployLog.failure_digest(FAILED_TRANSCRIPT)

    assert_equal "master", digest[:stage]
    assert_equal "master", digest[:app]
    assert_equal 1, digest[:exit]
    assert_equal ["probe_http: FAIL http://127.0.0.1:53187", "- authed metrics 401", "tts_socket false: nil (x2)"],
                 digest[:causes]
    assert_equal "/home/op/.pub5/deployments/deploy-x.log", digest[:transcript]
  end

  def test_failure_digest_reads_a_refused_stage_without_a_failed_banner
    text = "2026-11-25T12:19:25Z host=brgen pid=3 app=all stage=pin enter\n" \
           "vps-deploy: refused - cannot fast-forward /home/dev/pub5\n" \
           "2026-11-25T12:19:25Z host=brgen pid=3 app=all stage=pin finished exit=1\n"
    digest = Operator::DeployLog.failure_digest(text)

    assert_equal "pin", digest[:stage]
    assert_equal ["vps-deploy: refused - cannot fast-forward /home/dev/pub5"], digest[:causes]
    assert_nil Operator::DeployLog.failure_digest("vps-deploy: all ok\n")
  end

  def test_stage_labels_follow_stage_entries_and_fleet_moves
    labels = FAILED_TRANSCRIPT.lines.map(&:chomp).filter_map { |line| Operator::DeployLog.stage_label(line) }

    assert_equal %w[master master master], labels
    assert_equal "brgen start",
                 Operator::DeployLog.stage_label("2026-11-25T13:24:43Z host=b pid=2 app=brgen stage=start enter")
  end

  def test_finish_keeps_the_transcript_local_when_publishing_is_off
    Dir.mktmpdir do |dir|
      publisher = Master::Ground::PastePublisher.new(enabled: "0")
      log = Operator::DeployLog.new(app: "all", sha: "c" * 40, directory: dir, publisher:)
      log.finish(status: "failure", exit_code: 1)

      assert_includes File.read(log.path), "paste: not published; transcript kept at #{log.path}"
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
