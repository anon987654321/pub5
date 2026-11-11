# frozen_string_literal: true

require "fileutils"
require "json"
require "digest"
require "open3"
require_relative "../io/process_spawn"

module Operator
  # The MASTER suite across several processes. Workers are polled rather than
  # waited on synchronously, so a hung worker cannot hide its identity forever.
  module ParallelTests
    # The suite under test runs its own runner; it keeps its logs and lock apart (test_helper).
    LOG_DIR = ENV.fetch("MASTER_CHECK_LOG_DIR") { File.expand_path("../../.master/check", __dir__) }
RESULT_LINE = /\A\S+#\S+ = [\d.]+ s = [.FES]\s*\z/
# Minitest -v prints "Name = " before the test runs and its time and mark after;
# test_helper's start marker lands between them, so a real worker log reads
# "Name = test-start0: Name", any output the test printed, then "0.00 s = .".
# RESULT_LINE matched none of those, so every worker of every suite counted 0
# results against its summary and was reported incomplete with "missing final
# Minitest summary", even when the summary was the last line of its log.
SPLIT_START = /\A(\S+#\S+) = test-start0: (\S+#\S+)\s*\z/
SPLIT_RESULT = /\A[\d.]+ s = [.FES]\s*\z/
    REPORT_START = /\AFinished in /
    SUMMARY_LINE = /\A(\d+) runs?, (\d+) assertions?, (\d+) failures?, (\d+) errors?, (\d+) skips?\s*\z/i
    ENVIRONMENT_SKIP_LINE = /\Atest-environment-skip0: tag=([a-z][a-z0-9_.-]*) test=(\S+#\S+) reason=(.+)\z/
    DEFAULT_WORKER_TIMEOUT = 1800
    POLL_INTERVAL = 0.1

    module_function

    def jobs = [Integer(ENV.fetch("MASTER_TEST_JOBS", "3"), exception: false) || 3, 1].max

    # Read at run time so a test or caller can change the cadence after require.
    # Zero disables progress output; completed results remain available in JSON.
    def progress_every
      value = Integer(ENV.fetch("MASTER_TEST_PROGRESS_EVERY", "50"), exception: false)
      value && value >= 0 ? value : 50
    end

    def worker_timeout
      value = Float(ENV.fetch("MASTER_TEST_WORKER_TIMEOUT", DEFAULT_WORKER_TIMEOUT), exception: false)
      value && value.positive? ? value : DEFAULT_WORKER_TIMEOUT
    end

    def deal(files, count)
      buckets = Array.new(count) { [] }
      loads = Array.new(count, 0)
      weight = ->(path) { File.size?(path).to_i + 1 }
      files.sort_by { |path| [-weight.call(path), path] }.each do |path|
        lightest = loads.index(loads.min)
        buckets[lightest] << path
        loads[lightest] += weight.call(path)
      end
      buckets.reject(&:empty?)
    end

    # One suite at a time per checkout: the worker logs and suite-report.json have fixed
    # names, so a second suite overwrote the first one's evidence, and two suites on this
    # 8 GB machine starve each other. A held lock refuses rather than waits.
    def run(files, command:, out: $stdout)
      with_suite_lock(out) { run_locked(files, command:, out:) }
    end

    # Hold one checkout-wide lock across the whole measurement. The batch
    # reports are individual proofs; suite-report.json is their aggregate
    # receipt and remains "running" if the process is interrupted mid-series.
    def run_batches(files, command:, count:, out: $stdout)
      suite_files = Array(files).map(&:to_s).uniq.sort
      batches = balanced_batches(suite_files, count:)
      with_suite_lock(out) do
        run_id = "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{Process.pid}"
        revision = repository_revision
        report_path = File.join(LOG_DIR, "suite-report.json")
        progress = {
          "schema" => 1,
          "mode" => "batched",
          "status" => "running",
          "run_id" => run_id,
          "revision" => revision,
          "batch_count" => batches.size,
          "test_file_count" => suite_files.size,
          "test_files_sha256" => file_list_digest(suite_files),
          "completed_batches" => [],
        }
        write_receipt(report_path, progress)

        reports = batches.each_with_index.map do |batch_files, index|
          label = "#{run_id}-batch-#{index + 1}-of-#{batches.size}"
          batch_path = File.join(LOG_DIR, "suite-#{label}.json")
          out.puts "test-batch0: #{index + 1}/#{batches.size} files=#{batch_files.size} sha256=#{file_list_digest(batch_files)}"

          begin
            passed = run_locked(
              batch_files,
              command:,
              out:,
              batch_label: label,
              report_path: batch_path,
            )
            payload = JSON.parse(File.read(batch_path))
            raise "batch receipt label mismatch" unless payload["batch_label"] == label
            payload["batch_files"] = batch_files
            payload["batch_files_sha256"] = file_list_digest(batch_files)
            write_receipt(batch_path, payload)
          rescue StandardError => error
            passed = false
            payload = {
              "schema" => 1,
              "batch_label" => label,
              "status" => "delivery_failed",
              "error" => "#{error.class}: #{error.message}",
              "workers" => [],
              "completed_results_relayed" => 0,
            }
            write_receipt(batch_path, payload)
          end

          receipt = {
            "index" => index + 1,
            "file_count" => batch_files.size,
            "files_sha256" => file_list_digest(batch_files),
            "status" => payload["status"],
            "execution_passed" => passed,
            "receipt" => batch_path,
          }
          progress["completed_batches"] << receipt
          write_receipt(report_path, progress)
          { "index" => index + 1, "files" => batch_files, "path" => batch_path,
            "payload" => payload, "execution_passed" => passed }
        end

        aggregate = batch_aggregate(
          reports,
          files: suite_files,
          run_id:,
          revision:,
          batch_count: batches.size,
        )
        write_receipt(report_path, aggregate)
        out.puts "test-suite-batch-report0: #{report_path} batches=#{batches.size} " \
                 "files=#{suite_files.size} runs=#{aggregate.dig("summary", "runs")} status=#{aggregate["status"]}"
        aggregate["status"] == "passed"
      end
    rescue StandardError => error
      out.puts "test-batches0: delivery_failed #{error.class}: #{error.message}"
      false
    end

    def with_suite_lock(out)
      FileUtils.mkdir_p(LOG_DIR)
      File.open(File.join(LOG_DIR, "suite.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          out.puts "test-suite0: another suite holds #{LOG_DIR}/suite.lock (pid #{lock.read.strip}); not starting"
          return false
        end
        lock.truncate(0)
        lock.write(Process.pid.to_s)
        lock.flush
        yield
      end
    end

    def balanced_batches(files, count:)
      rows = Array(files).map(&:to_s).uniq.sort
      amount = Integer(count, exception: false)
      raise ArgumentError, "batch count must be a positive integer" unless amount&.positive?
      raise ArgumentError, "no test files to batch" if rows.empty?
      raise ArgumentError, "batch count cannot exceed test file count" if amount > rows.size

      deal(rows, amount)
    end

    def file_list_digest(files)
      Digest::SHA256.hexdigest(Array(files).map(&:to_s).sort.join("\0"))
    end

    def repository_revision
      output, status = Open3.capture2("git", "rev-parse", "HEAD", chdir: File.expand_path("../../..", __dir__))
      status.success? ? output.strip : nil
    rescue Errno::ENOENT
      nil
    end

    def write_receipt(path, payload)
      temporary = "#{path}.tmp-#{Process.pid}"
      FileUtils.mkdir_p(File.dirname(path))
      File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        file.write(JSON.pretty_generate(payload))
        file.write("\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if temporary
    end

    def batch_aggregate(reports, files:, run_id:, revision:, batch_count:)
      workers = reports.flat_map do |report|
        Array(report.dig("payload", "workers")).map do |worker|
          worker.merge("batch" => report.fetch("index"))
        end
      end
      summary_keys = %w[runs assertions failures errors skips]
      summary = summary_keys.to_h do |key|
        [key, workers.sum { |worker| worker.fetch("summary", {}).to_h.fetch(key, 0) }]
      end
      summary["workers"] = workers.size
      summary["complete_workers"] = workers.count { |worker| worker["summary_present"] }

      tagged_skips = workers.flat_map { |worker| Array(worker["environment_skips"]) }
      by_tag = tagged_skips.each_with_object(Hash.new(0)) { |row, counts| counts[row.fetch("tag")] += 1 }.sort.to_h
      skip_analysis = {
        "total" => summary.fetch("skips"),
        "environment_tagged" => tagged_skips.size,
        "unclassified" => [summary.fetch("skips") - tagged_skips.size, 0].max,
        "integrity" => tagged_skips.size <= summary.fetch("skips") ? "consistent" : "tagged_exceeds_summary",
        "by_tag" => by_tag,
      }
      expected_files = Array(files).map(&:to_s).uniq.sort
      covered_files = reports.flat_map { |report| Array(report.fetch("files")).map(&:to_s) }
      frequencies = covered_files.tally
      duplicates = frequencies.filter_map { |path, count| path if count > 1 }.sort
      missing = expected_files - frequencies.keys
      unexpected = frequencies.keys - expected_files
      file_coverage = {
        "complete" => duplicates.empty? && missing.empty? && unexpected.empty? &&
          covered_files.size == expected_files.size,
        "expected" => expected_files.size,
        "covered" => covered_files.uniq.size,
        "duplicates" => duplicates,
        "missing" => missing,
        "unexpected" => unexpected.sort,
      }
      batch_rows = reports.map do |report|
        payload = report.fetch("payload")
        {
          "index" => report.fetch("index"),
          "file_count" => report.fetch("files").size,
          "files" => report.fetch("files"),
          "files_sha256" => file_list_digest(report.fetch("files")),
          "status" => payload["status"],
          "execution_passed" => report.fetch("execution_passed"),
          "receipt" => report.fetch("path"),
        }
      end
      passed = reports.size == batch_count && file_coverage.fetch("complete") &&
        reports.all? do |report|
          report.fetch("execution_passed") && report.dig("payload", "status") == "passed"
        end

      {
        "schema" => 1,
        "mode" => "batched",
        "status" => passed ? "passed" : "failed_or_incomplete",
        "run_id" => run_id,
        "generated_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "revision" => revision,
        "runtime" => { "ruby" => RUBY_VERSION, "platform" => RUBY_PLATFORM },
        "batch_count" => batch_count,
        "completed_batches" => reports.size,
        "test_file_count" => files.size,
        "test_files_sha256" => file_list_digest(files),
        "file_coverage" => file_coverage,
        "jobs" => workers.size,
        "completed_results_relayed" => reports.sum { |report| report.dig("payload", "completed_results_relayed").to_i },
        "summary" => summary,
        "skip_analysis" => skip_analysis,
        "batches" => batch_rows,
        "workers" => workers,
      }
    end

    def run_locked(files, command:, out:, batch_label: nil, report_path: nil)
      workers = deal(files, jobs).each_with_index.map do |bucket, index|
        label = batch_label ? "-#{batch_label}" : ""
        start(bucket, log: File.join(LOG_DIR, "test-worker#{label}-#{index + 1}.log"), command:)
      end

      relay_errors = Queue.new
      progress = { completed: 0, last_emitted: 0, every: progress_every }
      relay = Thread.new do
        begin
          relay_results(workers, out, progress) { workers.all? { |worker| worker[:status] } }
        rescue StandardError => error
          relay_errors << "#{error.class}: #{error.message}"
        end
      end

      until workers.all? { |worker| worker[:status] }
        workers.each { |worker| poll(worker, out) unless worker[:status] }
        begin
          out.puts "test-relay0: #{relay_errors.pop(true)}"
        rescue ThreadError
          # No relay error was queued.
        end
        sleep POLL_INTERVAL unless workers.all? { |worker| worker[:status] }
      end

      relay.join
      begin
        out.puts "test-relay0: #{relay_errors.pop(true)}"
      rescue ThreadError
        # No relay error was queued.
      end
      workers.each do |worker|
        worker[:summary] = summary_data(worker)
        worker[:summary_present] = !worker[:summary].nil?
        worker[:failure_result_lines] = worker_failures(worker)
        worker[:environment_skips] = environment_skips(worker)
      end
      write_suite_report(workers, progress[:completed], out, batch_label:, report_path:)
      report(workers, out)
      workers.all? do |worker|
        summary = worker[:summary]
        worker[:status]&.success? && !worker[:timed_out] && worker[:summary_present] &&
          worker[:failure_result_lines].empty? && summary["failures"].zero? && summary["errors"].zero?
      end
    ensure
      workers&.each { |worker| terminate(worker) unless worker[:status] }
    end

    def start(bucket, log:, command:)
      marker_setting = ENV.fetch("MASTER_TEST_START_MARKERS", "1")
      env = { "MASTER_TEST_START_MARKERS" => marker_setting }
      pid = Process.spawn(Master::Io::ProcessSpawn.environment(env), *command.call(bucket), out: log, err: %i[child out], in: File::NULL, pgroup: true)
      {
        pid:, log:, offset: 0, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC),
        status: nil, timed_out: false, start_markers: marker_setting == "1"
      }
    end

    def poll(worker, out)
      result = Process.waitpid2(worker.fetch(:pid), Process::WNOHANG)
      if result
        worker[:status] = result.last
        return
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - worker.fetch(:started_at)
      return if elapsed <= worker_timeout

      worker[:timed_out] = true
      File.open(worker.fetch(:log), "a") do |file|
        file.puts "test-worker-timeout0: exceeded #{worker_timeout}s; terminating process group"
      end
      last_test = last_started_test(worker)
      out.puts "test-worker-timeout0: pid=#{worker.fetch(:pid)} elapsed=#{elapsed.round(1)}s last_test=#{last_test || "unknown"} log=#{worker.fetch(:log)}"
      terminate(worker)
    end

    def terminate(worker)
      pid = worker.fetch(:pid)
      begin
        Process.kill("TERM", -pid)
      rescue Errno::ESRCH
        # The worker exited between the poll and signal.
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      loop do
        result = Process.waitpid2(pid, Process::WNOHANG)
        if result
          worker[:status] = result.last
          return
        end
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.05
      end

      begin
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH
        # Already gone.
      end
      _pid, status = Process.waitpid2(pid)
      worker[:status] = status
    rescue Errno::ECHILD
      worker[:status] ||= nil
    end

    def relay_results(workers, out, progress)
      until yield
        relay_once(workers, out, progress)
        sleep 1
      end
      relay_once(workers, out, progress)
    end

    def relay_once(workers, out, progress)
      workers.each do |worker|
        logical_lines(fresh_lines(worker), worker).grep(RESULT_LINE).each do |line|
          out.puts line
          progress[:completed] += 1
          if progress[:every].positive? && progress[:completed] - progress[:last_emitted] >= progress[:every]
            progress[:last_emitted] = progress[:completed]
            out.puts "test-progress0: completed_results=#{progress[:completed]}"
          end
        end
      end
      out.flush
    end

    def fresh_lines(worker)
      text = File.open(worker.fetch(:log), "rb") { |file| file.seek(worker.fetch(:offset)) && file.read.to_s }
      complete = String.new(text[/\A.*\n/m].to_s)
      worker[:offset] += complete.bytesize
      complete.force_encoding(Encoding::UTF_8).scrub.lines(chomp: true)
    end

    # The log as two lines per test, "test-start0: Name" and "Name = 0.00 s = .", however the two
    # streams interleaved. +state+ carries a test whose result has not arrived yet (relay_once reads
    # the log in pieces).
    def logical_lines(lines, state = {})
      lines.each_with_object([]) do |line, out|
        if (split = SPLIT_START.match(line))
          out << "test-start0: #{split[2]}"
          state[:pending] = split[1]
        elsif state[:pending] && SPLIT_RESULT.match?(line)
          out << "#{state.delete(:pending)} = #{line.strip}"
        else
          out << line
        end
      end
    end

    def log_lines(worker)
      read = File.foreach(worker.fetch(:log), chomp: true, encoding: "UTF-8", invalid: :replace, undef: :replace)
      logical_lines(read)
    end

    def last_started_test(worker)
      last = nil
      log_lines(worker).each do |line|
        last = line.delete_prefix("test-start0: ").strip if line.start_with?("test-start0: ")
      end
      last
    rescue Errno::ENOENT
      nil
    end

    def summary_data(worker)
      results = []
      starts = []
      summary = nil

      log_lines(worker).each do |line|
        results << line[/\A(\S+#\S+) = /, 1] if RESULT_LINE.match?(line)
        starts << line.delete_prefix("test-start0: ").strip if line.start_with?("test-start0: ")

        if (match = SUMMARY_LINE.match(line))
          summary = {
            "runs" => match[1].to_i,
            "assertions" => match[2].to_i,
            "failures" => match[3].to_i,
            "errors" => match[4].to_i,
            "skips" => match[5].to_i,
          }
        end
      end

      return unless summary && summary["runs"] == results.size
      # A test that started and never reported is the crash this check exists for. The count
      # alone also failed a class that overrides run (TestCliBootE2e) and prints no marker.
      return if worker[:start_markers] && (starts - results).any?

      summary.merge("result_lines" => results.size, "start_markers" => starts.size)
    rescue Errno::ENOENT
      nil
    end

    def worker_failures(worker)
      failures = []
      log_lines(worker).each do |line|
        failures << line if RESULT_LINE.match?(line) && line.match?(/ = [FE]\s*\z/)
      end
      failures
    rescue Errno::ENOENT
      []
    end

    def environment_skips(worker)
      log_lines(worker).filter_map do |line|
        match = ENVIRONMENT_SKIP_LINE.match(line)
        next unless match

        { "tag" => match[1], "test" => match[2], "reason" => match[3] }
      end
    rescue Errno::ENOENT
      []
    end

    def worker_outcome(worker)
      summary = worker[:summary]
      return "timeout" if worker[:timed_out]
      return "incomplete" unless worker[:summary_present]
      return "failed" unless worker[:status]&.success?
      return "failed" unless worker[:failure_result_lines].empty?
      return "failed" if summary["failures"].positive? || summary["errors"].positive?

      "passed"
    end

    def known_red?(worker)
      summary = worker[:summary]
      red_summary = summary && (summary["failures"].positive? || summary["errors"].positive?)
      red_exit = worker[:status] && !worker[:status].success?
      !!(red_summary || !worker[:failure_result_lines].empty? || red_exit)
    end

    def write_suite_report(workers, completed_results, out, batch_label: nil, report_path: nil)
      tagged_skips = workers.flat_map { |worker| Array(worker[:environment_skips]) }
      total_skips = workers.sum { |worker| worker[:summary].to_h.fetch("skips", 0) }
      by_tag = tagged_skips.each_with_object(Hash.new(0)) { |row, counts| counts[row.fetch("tag")] += 1 }.sort.to_h
      skip_analysis = {
        "total" => total_skips,
        "environment_tagged" => tagged_skips.size,
        "unclassified" => [total_skips - tagged_skips.size, 0].max,
        "integrity" => tagged_skips.size <= total_skips ? "consistent" : "tagged_exceeds_summary",
        "by_tag" => by_tag,
      }
      payload = {
        "schema" => 1,
        "skip_analysis" => skip_analysis,
        "status" => (workers.all? { |worker| worker_outcome(worker) == "passed" } ? "passed" : "failed_or_incomplete"),
        "completed_results_relayed" => completed_results,
        "jobs" => workers.size,
        "workers" => workers.each_with_index.map do |worker, index|
          {
            "index" => index + 1,
            "pid" => worker[:pid],
            "log" => worker[:log],
            "exit_status" => worker[:status]&.exitstatus,
            "success" => worker[:status]&.success? || false,
            "timed_out" => !!worker[:timed_out],
            "outcome" => worker_outcome(worker),
            "summary_present" => !!worker[:summary_present],
            "summary" => worker[:summary],
            "last_started_test" => last_started_test(worker),
            "failure_result_lines" => worker[:failure_result_lines],
            "known_red" => known_red?(worker),
            "environment_skips" => Array(worker[:environment_skips]),
          }
        end,
      }
      payload["batch_label"] = batch_label if batch_label
      path = report_path || File.join(LOG_DIR, "suite-report.json")
      File.write(path, JSON.pretty_generate(payload) + "\n")
      out.puts "test-suite-report0: #{path} completed_results=#{completed_results} status=#{payload["status"]}"
      tags = by_tag.map { |tag, count| "#{tag}:#{count}" }.join(",")
      out.puts "test-skip-summary0: total=#{total_skips} environment_tagged=#{tagged_skips.size} " \
               "unclassified=#{skip_analysis["unclassified"]}#{tags.empty? ? "" : " by_tag=#{tags}"}"

      incomplete = payload["workers"].reject { |worker| worker["outcome"] == "passed" }
      return if incomplete.empty?

      out.puts "test-suite-incomplete-workers0: #{incomplete.size}"
      incomplete.each do |worker|
        out.puts "test-worker-last0: #{worker["last_started_test"] || "unknown"}" if worker["last_started_test"]
        out.puts "  worker=#{worker["index"]} outcome=#{worker["outcome"]} timed_out=#{worker["timed_out"]} " \
                 "summary=#{worker["summary_present"]} exit=#{worker["exit_status"].inspect}"
      end
    rescue StandardError => error
      out.puts "test-suite-report0: failed #{error.class}: #{error.message}"
    end

    def report(workers, out)
      workers.each_with_index do |worker, index|
        lines = File.read(worker.fetch(:log), encoding: "UTF-8", invalid: :replace, undef: :replace).lines
        start = lines.index { |line| line.match?(REPORT_START) } || [lines.size - 40, 0].max
        suffix = []
        suffix << "TIMEOUT" if worker[:timed_out]
        suffix << "INCOMPLETE" unless worker[:summary_present]
        label = suffix.empty? ? "" : ", #{suffix.join(", ")}"
        out.puts "", "worker #{index + 1} of #{workers.size} (pid #{worker.fetch(:pid)}#{label}):", *lines.drop(start).map(&:chomp)
        out.puts "test-worker-incomplete0: missing final Minitest summary" unless worker[:summary_present]
        if worker[:timed_out] || worker[:failure_result_lines]&.any? || worker[:summary].to_h.values_at("failures", "errors").compact.any?(&:positive?)
          out.puts "test-worker-last0: #{last_started_test(worker) || "unknown"}"
        end
      end
    end
  end
end
