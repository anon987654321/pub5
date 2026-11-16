# frozen_string_literal: true

require "fileutils"
require "time"
require_relative "../io/exec"
require_relative "../trace/dmesg"

module Operator
  class CheckRunner
    Result = Struct.new(:name, :success, :output, keyword_init: true)

    TimeoutStatus = Struct.new(:success?) do
      def initialize = super(false)
    end

    attr_reader :results, :log_path

    def initialize(prefix:, root:, timeout:, quiet: false, log_path: nil)
      @prefix = prefix
      @root = root
      @timeout = timeout
      @quiet = quiet
      @results = []
      @log_path = log_path && File.expand_path(log_path, @root)
      prepare_run_log if @log_path
    end

    # The timeout is a hang guard, not a performance budget — a hung step is
    # infinite, so any generous ceiling catches it equally well. Treating it as
    # a budget is how `rake test` at 247s started failing a 360s limit on any
    # machine that was also doing something else, and reported it as
    # "first_failure: test / category: true_violation", i.e. as if a unit test
    # had broken. A check that goes red for reasons unrelated to the code is a
    # check people learn to ignore.
    #
    # So: warn as soon as a step spends most of its allowance, while it is still
    # passing. The next person then finds out from a green run that a step is
    # creeping up, instead of from a red one after it has already tipped over.
    SLOW_STEP_FRACTION = 0.6

    def run(name, *cmd, env: {})
      unit = "#{@prefix}#{@results.size + 1}"
      Master::Trace::Dmesg.attach(unit, "#{@prefix}0", name) unless @quiet
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out, status = capture(env, *cmd)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      ok = status.success?
      @results << Result.new(name:, success: ok, output: out)
      record_run_step(name, ok, elapsed, out)
      report(unit, name, ok, elapsed)
      Master::Trace::Dmesg::Report.print(unit, out, parent: "#{@prefix}0") if !out.empty? && (!ok || ENV["CHECK_VERBOSE"] == "1")
      ok
    end

    private

    # One private, stable artifact for the whole invocation. Per-step logs remain
    # beside it for live StepWatch; this file makes a failed run easy to attach.
    def prepare_run_log
      directory = File.dirname(@log_path)
      cursor = directory
      while cursor != File.dirname(cursor)
        raise IOError, "check log path crosses a symlink: #{cursor}" if File.symlink?(cursor)
        cursor = File.dirname(cursor)
      end

      FileUtils.mkdir_p(directory, mode: 0o700)
      File.chmod(0o700, directory)
      raise IOError, "check log is a symlink" if File.symlink?(@log_path)

      File.open(@log_path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        File.chmod(0o600, @log_path)
        file.write("MASTER check log\nstarted_at: #{Time.now.utc.iso8601}\nroot: #{@root}\nprefix: #{@prefix}\n\n")
        file.flush
        file.fsync
      end
    rescue StandardError => e
      @log_error = "#{e.class}: #{e.message}"
      @log_path = nil
      Master::Trace::Dmesg.status("checklog0", "cannot create combined log, #{@log_error}") unless @quiet
    end

    def record_run_step(name, ok, elapsed, output)
      return unless @log_path
      raise IOError, "check log is a symlink" if File.symlink?(@log_path)

      File.open(@log_path, File::WRONLY | File::APPEND | File::CREAT, 0o600) do |file|
        File.chmod(0o600, @log_path)
        file.write("=== #{name} | #{ok ? "PASS" : "FAIL"} | #{elapsed.round(2)}s ===\n")
        file.write(output.to_s)
        file.write("\n") unless output.to_s.empty? || output.to_s.end_with?("\n")
        file.write("\n")
        file.flush
        file.fsync
      end
    rescue StandardError => e
      @log_error ||= "#{e.class}: #{e.message}"
      @log_path = nil
      Master::Trace::Dmesg.status("checklog0", "combined log incomplete, #{@log_error}") unless @quiet
    end

    def report(unit, name, ok, elapsed)
      return if @quiet

      Master::Trace::Dmesg.status(unit, ok ? "clean" : "failed")
      return unless ok && elapsed > @timeout * SLOW_STEP_FRACTION

      Master::Trace::Dmesg.status(
        unit,
        "#{elapsed.round}s of #{@timeout}s timeout, consider splitting #{name}",
      )
    end

    # A step writes to .master/check/<name>.log as it runs, and StepWatch reads it while it does:
    # a buffered step said nothing until it ended, so a suite that died after 3,632 tests and one
    # that was still running looked the same for twenty minutes.
    #
    # A step is a fresh child that activates its own bundle. The booted parent's group selection must
    # not follow it: a deploy bundle sets BUNDLE_WITHOUT=development:test, which hides the :test
    # group, so every test step dies "minitest is not part of the bundle" before its first line. The
    # step's own boot picks its groups (a test boot keeps :test). The rest of the bundle context is
    # left alone on purpose: the child needs the parent's BUNDLE_PATH, GEM_HOME, GEM_PATH and
    # BUNDLER_VERSION to reach the same bundle without re-installing or re-triggering Bundler's
    # auto-switch.
    CHILD_ENV_CLEARED = %w[BUNDLE_ONLY BUNDLE_WITH BUNDLE_WITHOUT].freeze

    def capture(env, *cmd)
      log = StepWatch.log_path(cmd.last(2).join(" "))
      child_env = CHILD_ENV_CLEARED.to_h { |key| [key, nil] }.merge(env)
      pid = Process.spawn(
        Master::Io::ProcessSpawn.environment(child_env), *cmd,
        chdir: @root, in: File::NULL, out: log, err: %i[child out], pgroup: true,
      )
      watch = StepWatch.new(log, unit: "#{@prefix}#{@results.size + 1}") unless @quiet

      status = wait_bounded(pid)
      output = File.read(log, encoding: "UTF-8", invalid: :replace, undef: :replace)
      return [output, status] if status

      ["#{output}\nstep timed out after #{@timeout}s: #{cmd.join(' ')}\n", TimeoutStatus.new]
    ensure
      watch&.stop
    end

    # The exit status, or nil after the step's whole process group is killed at the timeout.
    def wait_bounded(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        status = Process.wait2(pid, Process::WNOHANG)&.last
        return status if status

        sleep 0.05
      end
      stop_group(pid)
      nil
    end

    # ESRCH: the group is gone. EPERM: macOS answers so for a group left holding only a zombie.
    def stop_group(pid)
      Process.kill("TERM", -pid)
      sleep 1

      Process.kill("KILL", -pid)
    rescue Errno::ESRCH, Errno::EPERM
      :already_gone
    ensure
      reap(pid)
    end

    def reap(pid)
      Process.wait(pid)
    rescue Errno::ECHILD
      :already_reaped
    end
  end
end

require_relative "check_runner/step_watch"
