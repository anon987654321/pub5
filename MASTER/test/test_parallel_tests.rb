# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "stringio"
require "json"
require_relative "../lib/operator/parallel_tests"

class TestParallelTests < Minitest::Test
  Runner = Operator::ParallelTests

  def setup
    @previous_jobs = ENV["MASTER_TEST_JOBS"]
    @previous_timeout = ENV["MASTER_TEST_WORKER_TIMEOUT"]
    @previous_progress = ENV["MASTER_TEST_PROGRESS_EVERY"]
    ENV["MASTER_TEST_JOBS"] = "2"
    ENV["MASTER_TEST_PROGRESS_EVERY"] = "1"
  end

  def teardown
    @previous_jobs.nil? ? ENV.delete("MASTER_TEST_JOBS") : ENV["MASTER_TEST_JOBS"] = @previous_jobs
    @previous_timeout.nil? ? ENV.delete("MASTER_TEST_WORKER_TIMEOUT") : ENV["MASTER_TEST_WORKER_TIMEOUT"] = @previous_timeout
    @previous_progress.nil? ? ENV.delete("MASTER_TEST_PROGRESS_EVERY") : ENV["MASTER_TEST_PROGRESS_EVERY"] = @previous_progress
  end

  def test_environment_skip_helper_emits_a_machine_readable_reason
    _stdout, stderr = capture_subprocess_io do
      assert_raises(Minitest::Skip) do
        skip_for_environment("Browser", reason: "Chrome unavailable\nfor this host")
      end
    end

    assert_raises(ArgumentError) { skip_for_environment("browser tag", reason: "bad tag") }
    assert_raises(ArgumentError) { skip_for_environment("browser", reason: "   ") }
    assert_includes stderr, "test-environment-skip0: tag=browser"
    assert_includes stderr, "reason=Chrome unavailable for this host"
  end

  # A second suite refused while the first holds the lock: both share fixed log names.
  def test_a_second_suite_refuses_while_one_runs
    FileUtils.mkdir_p(Runner::LOG_DIR)
    File.open(File.join(Runner::LOG_DIR, "suite.lock"), File::RDWR | File::CREAT) do |held|
      held.flock(File::LOCK_EX)
      out = StringIO.new
      started = false

      refute Runner.run(%w[ok], command: ->(_files) { started = true }, out:)
      refute started
      assert_match(/another suite holds/, out.string)
    end
  end

  def test_results_pass_through_and_a_failed_worker_fails_the_run
    out = StringIO.new
    passed = Runner.run(%w[ok bad], command: method(:fake_worker), out:)

    refute passed
    assert_includes out.string, "TestOk#test_one = 0.00 s = ."
    assert_includes out.string, "TestBad#test_two = 0.00 s = F"
    assert_includes out.string, "TestBad#test_two [x.rb:1]:"
  end

  def test_a_hung_worker_times_out_and_reports_its_log
    ENV["MASTER_TEST_WORKER_TIMEOUT"] = "0.2"
    out = StringIO.new
    command = lambda do |files|
      if files.include?("hang")
        [RbConfig.ruby, "-e", "STDERR.puts 'test-start0: HungSuite#test_stuck'; STDERR.flush; sleep 30"]
      else
        [RbConfig.ruby, "-e", "puts 'test-start0: TestOk#test_one'; puts 'TestOk#test_one = 0.00 s = .'; puts 'Finished in 0.01s'; puts '1 runs, 1 assertions, 0 failures, 0 errors, 0 skips'; exit 0"]
      end
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    passed = Runner.run(%w[hang ok], command:, out:)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    refute passed
    assert_operator elapsed, :<, 8
    assert_includes out.string, "test-worker-timeout0:"
    assert_includes out.string, "last_test=HungSuite#test_stuck"
    assert_includes out.string, "TIMEOUT"
  end

  def test_successful_exit_without_minitest_summary_is_incomplete
    out = StringIO.new
    command = lambda do |_files|
      [RbConfig.ruby, "-e", "STDERR.puts 'test-start0: Example#test_exits_early'; exit 0"]
    end

    refute Runner.run(%w[early-exit], command:, out:)
    assert_includes out.string, "INCOMPLETE"
    assert_includes out.string, "test-start0: Example#test_exits_early"
    assert_includes out.string, "test-worker-incomplete0: missing final Minitest summary"
    assert_includes out.string, "test-worker-last0: Example#test_exits_early"
  end

  def test_progress_and_suite_report_name_incomplete_workers
    out = StringIO.new
    command = lambda do |files|
      if files.include?("early")
        [RbConfig.ruby, "-e", "STDERR.puts 'test-start0: Early#test_gone'; exit 0"]
      else
        [RbConfig.ruby, "-e", "puts 'test-start0: Ok#test_one'; puts 'Ok#test_one = 0.00 s = .'; puts 'Finished in 0.01s'; puts '1 runs, 1 assertions, 0 failures, 0 errors, 0 skips'; exit 0"]
      end
    end

    refute Runner.run(%w[early ok], command:, out:)
    assert_includes out.string, "test-progress0: completed_results=1"
    assert_includes out.string, "test-suite-report0:"
    assert_includes out.string, "test-suite-incomplete-workers0:"
    assert_includes out.string, "test-worker-last0: Early#test_gone"

    report_path = File.join(Runner::LOG_DIR, "suite-report.json")
    assert File.file?(report_path), "expected #{report_path}"
    payload = JSON.parse(File.read(report_path))
    assert_equal 1, payload["schema"]
    assert_equal 1, payload["completed_results_relayed"]
    incomplete = payload["workers"].select { |worker| worker["outcome"] == "incomplete" }
    refute_empty incomplete
    assert_equal "Early#test_gone", incomplete.first["last_started_test"]
  end

  def test_environment_tagged_skips_are_grouped_in_the_suite_receipt
    script = [
      '$stdout.sync = true',
      'puts "test-start0: BrowserSuite#test_needs_chrome"',
      'STDERR.puts "test-environment-skip0: tag=browser test=BrowserSuite#test_needs_chrome reason=Chrome unavailable"',
      'puts "BrowserSuite#test_needs_chrome = 0.00 s = S"',
      'puts "Finished in 0.01s"',
      'puts "1 runs, 0 assertions, 0 failures, 0 errors, 1 skips"'
    ].join("\n")
    out = StringIO.new

    assert Runner.run(%w[browser-skip], command: ->(_files) { [RbConfig.ruby, "-e", script] }, out:), out.string
    assert_includes out.string, "test-skip-summary0: total=1 environment_tagged=1 unclassified=0 by_tag=browser:1"

    payload = JSON.parse(File.read(File.join(Runner::LOG_DIR, "suite-report.json")))
    assert_equal(
      { "total" => 1, "environment_tagged" => 1, "unclassified" => 0,
        "integrity" => "consistent", "by_tag" => { "browser" => 1 } },
      payload.fetch("skip_analysis")
    )
    assert_equal "Chrome unavailable",
                 payload.fetch("workers").first.fetch("environment_skips").first.fetch("reason")
  end

  def test_exit_zero_with_failure_summary_still_fails_the_run
    out = StringIO.new
    command = lambda do |_files|
      [RbConfig.ruby, "-e", "puts 'test-start0: Example#test_false_green'; puts 'Example#test_false_green = 0.00 s = F'; puts 'Finished in 0.01s'; puts '1 runs, 1 assertions, 1 failures, 0 errors, 0 skips'; exit 0"]
    end

    refute Runner.run(%w[false-green], command:, out:)
    payload = JSON.parse(File.read(File.join(Runner::LOG_DIR, "suite-report.json")))
    assert_equal "failed", payload.fetch("workers").first.fetch("outcome")
    assert payload.fetch("workers").first.fetch("known_red")
  end

  def test_one_job_rake_test_still_uses_the_supervised_runner
    rakefile = File.read(File.expand_path("../Rakefile", __dir__))

    assert_includes rakefile, "Operator::ParallelTests.run(MASTER_TEST_FILES.to_a, command:)"
    refute_includes rakefile, 'next Rake::Task[:"test:serial"].invoke if Operator::ParallelTests.jobs == 1'
  end

  # The shape a real worker writes: -v prints "Name = " first, the start marker
  # lands on the same line from stderr, the test prints, and the mark comes last.
  def test_a_worker_whose_marker_split_its_result_line_is_complete_and_green
    script = [
      "$stdout.sync = true", 'print "TestOk#test_one = "', 'STDERR.puts "test-start0: TestOk#test_one"',
      'puts "scan0: something the test printed"', 'puts "0.00 s = ."', 'puts "Finished in 0.01s"',
      'puts "1 runs, 1 assertions, 0 failures, 0 errors, 0 skips"'
    ].join("\n")

    out = StringIO.new

    assert Runner.run(%w[ok], command: ->(_files) { [RbConfig.ruby, "-e", script] }, out:), out.string
    assert_includes out.string, "TestOk#test_one = 0.00 s = ."
    payload = JSON.parse(File.read(File.join(Runner::LOG_DIR, "suite-report.json")))
    assert_equal "passed", payload.fetch("workers").first.fetch("outcome")
  end

  # A class that overrides run (TestCliBootE2e) reports results with no start
  # marker; only a start with no result is a test that never finished.
  def test_a_result_without_a_start_marker_is_complete_and_a_start_without_a_result_is_not
    finished = ['puts "Skipped#test_one = 0.00 s = S"', 'puts "1 runs, 0 assertions, 0 failures, 0 errors, 1 skips"']
    crashed = ['puts "test-start0: Gone#test_two"', *finished]
    run = lambda do |lines|
      Runner.run(%w[x], command: ->(_files) { [RbConfig.ruby, "-e", lines.join("\n")] }, out: StringIO.new)
    end

    assert run.call(finished), "a result without a start marker read as incomplete"
    refute run.call(crashed), "a start without a result read as complete"
  end

  def test_balanced_batches_cover_each_file_once_and_are_deterministic
    Dir.mktmpdir do |dir|
      files = { "a" => 900, "b" => 500, "c" => 400, "d" => 100 }.map do |name, size|
        File.join(dir, name).tap { |path| File.write(path, "x" * size) }
      end

      batches = Runner.balanced_batches(files.reverse, count: 2)

      assert_equal [[files[0], files[3]], [files[1], files[2]]], batches
      assert_equal files.sort, batches.flatten.sort
      assert_equal batches, Runner.balanced_batches(files, count: 2)
    end
  end

  def test_run_batches_writes_per_batch_proofs_and_an_aggregate_baseline_receipt
    previous_jobs = ENV["MASTER_TEST_JOBS"]
    ENV["MASTER_TEST_JOBS"] = "1"
    files = %w[a.rb b.rb c.rb d.rb]
    command = lambda do |bucket|
      names = bucket.map { |path| "#{File.basename(path, ".rb").capitalize}Suite#test_one" }
      lines = ["$stdout.sync = true"]
      names.each do |name|
        lines << "puts 'test-start0: #{name}'"
        lines << "puts '#{name} = 0.00 s = .'"
      end
      lines << "puts 'Finished in 0.01s'"
      lines << "puts '#{names.size} runs, #{names.size} assertions, 0 failures, 0 errors, 0 skips'"
      [RbConfig.ruby, "-e", lines.join("\n")]
    end
    out = StringIO.new

    assert Runner.run_batches(files, command:, count: 2, out:), out.string

    report_path = File.join(Runner::LOG_DIR, "suite-report.json")
    aggregate = JSON.parse(File.read(report_path))
    assert_equal "batched", aggregate.fetch("mode")
    assert_equal "passed", aggregate.fetch("status")
    assert_equal 2, aggregate.fetch("batch_count")
    assert_equal 2, aggregate.fetch("completed_batches")
    assert_equal 4, aggregate.fetch("test_file_count")
    assert_equal 4, aggregate.dig("summary", "runs")
    assert_equal 4, aggregate.dig("summary", "assertions")
    assert_equal 4, aggregate.fetch("completed_results_relayed")
    assert_equal 2, aggregate.fetch("batches").size
    batch_files = aggregate.fetch("batches").flat_map { |batch| batch.fetch("files") }
    assert_equal files.sort, batch_files.sort
    assert_equal files.size, batch_files.uniq.size
    assert_equal({ "complete" => true, "expected" => 4, "covered" => 4,
                   "duplicates" => [], "missing" => [], "unexpected" => [] },
                 aggregate.fetch("file_coverage"))
    aggregate.fetch("batches").each do |batch|
      assert File.file?(batch.fetch("receipt"))
      per_batch = JSON.parse(File.read(batch.fetch("receipt")))
      assert_equal batch.fetch("files"), per_batch.fetch("batch_files")
      assert_equal batch.fetch("files_sha256"), per_batch.fetch("batch_files_sha256")
      assert_equal batch.fetch("index"),
                   per_batch.fetch("batch_label").match(/batch-(\d+)-of-/).captures.first.to_i
      per_batch.fetch("workers").each do |worker|
        assert File.basename(worker.fetch("log")).include?("-batch-")
        assert File.file?(worker.fetch("log"))
      end
    end
    assert_includes out.string, "test-suite-batch-report0:"
  ensure
    previous_jobs.nil? ? ENV.delete("MASTER_TEST_JOBS") : ENV["MASTER_TEST_JOBS"] = previous_jobs
  end

  def test_batch_aggregate_refuses_duplicate_or_missing_test_files
    reports = [
      { "index" => 1, "files" => %w[a.rb b.rb],
        "payload" => { "status" => "passed", "workers" => [], "completed_results_relayed" => 0 },
        "execution_passed" => true, "path" => "batch-1.json" },
      { "index" => 2, "files" => %w[b.rb d.rb],
        "payload" => { "status" => "passed", "workers" => [], "completed_results_relayed" => 0 },
        "execution_passed" => true, "path" => "batch-2.json" },
    ]

    aggregate = Runner.batch_aggregate(
      reports, files: %w[a.rb b.rb c.rb d.rb], run_id: "receipt-test",
      revision: "deadbeef", batch_count: 2
    )

    assert_equal "failed_or_incomplete", aggregate.fetch("status")
    assert_equal false, aggregate.dig("file_coverage", "complete")
    assert_equal ["b.rb"], aggregate.dig("file_coverage", "duplicates")
    assert_equal ["c.rb"], aggregate.dig("file_coverage", "missing")
  end

  def test_rakefile_exposes_the_bounded_batch_task
    rakefile = File.read(File.expand_path("../Rakefile", __dir__))

    assert_includes rakefile, "task :batch do"
    assert_includes rakefile, "MASTER_TEST_BATCHES"
    assert_includes rakefile, "Operator::ParallelTests.run_batches"
    assert_includes rakefile, "MASTER_TEST_FILES.to_a"
  end

  def test_files_are_dealt_largest_first_onto_the_lightest_worker
    buckets = Dir.mktmpdir { |dir| Runner.deal(sized_files(dir), 2).map { |bucket| bucket.map { File.basename(_1) } } }
    assert_equal [%w[a d], %w[b c]], buckets
  end

  def sized_files(dir)
    { "a" => 900, "b" => 500, "c" => 400, "d" => 100 }.map do |name, size|
      File.join(dir, name).tap { |path| File.write(path, "x" * size) }
    end
  end

  def fake_worker(files)
    bad = files.first == "bad"
    test = bad ? "TestBad#test_two" : "TestOk#test_one"
    failure = bad ? "puts \"  1) Failure:\", \"#{test} [x.rb:1]:\"" : ""
    script = [
      "puts \"test-start0: #{test}\"",
      "puts \"#{test} = 0.00 s = #{bad ? "F" : "."}\"", "puts \"Finished in 0.1s\"", failure,
      "puts \"1 runs, 1 assertions, 0 failures, 0 errors, 0 skips\"", "exit(#{!bad})"
    ].join("\n")
    [RbConfig.ruby, "-e", script]
  end
end
