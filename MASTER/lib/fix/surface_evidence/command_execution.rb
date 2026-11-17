# frozen_string_literal: true

module Master
  module Fix
    class SurfaceEvidence
      # The command runner every probe and test receipt goes through: popen3
      # with a process group, a hard deadline, output draining and the
      # group-signalled shutdown that never falls back to a numeric child PID.
      private

      def execute_command(argv, chdir:, env: {}, deadline:)
        command = Array(argv).map(&:to_s)
        return { "status" => "inconclusive", "message" => "command deadline exhausted", "timed_out" => true } if deadline_remaining(deadline) <= 0

        run_command_with_limits(command, chdir:, env:, deadline:)
      rescue Errno::ENOENT => e
        { "status" => "inconclusive", "message" => "executable unavailable: #{error_text(e)}" }
      rescue StandardError => e
        { "status" => "inconclusive", "message" => "command runner failed: #{error_text(e)}" }
      end

      def run_command_with_limits(command, chdir:, env:, deadline:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timeout = [DEFAULT_COMMAND_TIMEOUT, deadline_remaining(deadline)].min
        stdout = +""
        stderr = +""
        state = spawn_command_process(command, chdir:, env:, started:, timeout:, stdout:, stderr:)
        command_outcome(command, state, started:, timeout:, stdout:, stderr:)
      end

      def spawn_command_process(command, chdir:, env:, started:, timeout:, stdout:, stderr:)
        state = { timed_out: false, termination_confirmed: true, status: nil }

        Open3.popen3(Master::Io::ProcessSpawn.environment(ENV.to_h.merge(env.transform_keys(&:to_s).transform_values(&:to_s))), *command, chdir:, pgroup: true) do |stdin, out, err, wait_thr|
          stdin.close
          stdout_reader = Thread.new { drain_output(out, stdout) }
          stderr_reader = Thread.new { drain_output(err, stderr) }
          supervise_command_process(wait_thr, stdout_reader, stderr_reader, started + timeout, state, out, err)
          state[:status] = wait_thr.value unless wait_thr.alive?
        end

        state
      end

      def supervise_command_process(wait_thr, stdout_reader, stderr_reader, deadline, state, out, err)
        await_process_or_deadline(wait_thr, stdout_reader, stderr_reader, deadline, state)
        terminate_command_process(wait_thr, stdout_reader, stderr_reader, out, err, state) if state[:timed_out]
      end

      def await_process_or_deadline(wait_thr, stdout_reader, stderr_reader, deadline, state)
        loop do
          break unless wait_thr.alive? || stdout_reader.alive? || stderr_reader.alive?

          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if remaining <= 0
            state[:timed_out] = true
            break
          end

          if wait_thr.alive?
            wait_thr.join([remaining, 0.05].min)
          else
            sleep([remaining, 0.01].min)
          end
        end
      end

      def terminate_command_process(wait_thr, stdout_reader, stderr_reader, out, err, state)
        confirmed = stop_process_group(wait_thr.pid)
        wait_thr.join(2)
        # wait_thr is the direct child this method spawned. If group signalling
        # was denied, KILL that exact still-owned child; never fall back to a
        # numeric PID after ESRCH or after the wait handle has completed.
        kill_owned_child(wait_thr) if wait_thr.alive?
        wait_thr.join(2) if wait_thr.alive?
        confirmed &&= !wait_thr.alive? && !process_group_alive?(wait_thr.pid)
        terminate_command_readers(out, stdout_reader, err, stderr_reader)
        confirmed &&= !stdout_reader.alive? && !stderr_reader.alive?
        state[:termination_confirmed] = confirmed
      end

      def terminate_command_readers(out, stdout_reader, err, stderr_reader)
        [[out, stdout_reader], [err, stderr_reader]].each do |io, reader|
          reader.join(0.2)
          next unless reader.alive?

          io.close rescue nil
          reader.kill
          reader.join(0.2)
        end
      end

      def command_outcome(command, state, started:, timeout:, stdout:, stderr:)
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        code = state[:status]&.exitstatus
        {
          "status" => command_outcome_status(state, code),
          "exit_status" => code,
          "timed_out" => state[:timed_out],
          "termination_confirmed" => state[:termination_confirmed],
          "duration_ms" => elapsed,
          "stdout_sha256" => Digest::SHA256.hexdigest(stdout),
          "stderr_sha256" => Digest::SHA256.hexdigest(stderr),
          "message" => command_outcome_message(state, code, timeout, stdout, stderr),
          "command" => command.first(4).map { |item| File.basename(item) },
        }.compact
      end

      def command_outcome_status(state, code)
        if state[:timed_out]
          "inconclusive"
        elsif code == 0
          "passed"
        else
          "failed"
        end
      end

      def command_outcome_message(state, code, timeout, stdout, stderr)
        if state[:timed_out]
          suffix = state[:termination_confirmed] ? "process group stopped" : "process-group shutdown unverified"
          "command timed out after #{timeout.round(1)}s; #{suffix}"
        elsif code != 0
          safe_text((stderr.empty? ? stdout : stderr).lines.last(3).join(" ").strip, 220)
        end
      end

      def drain_output(io, buffer = +"")
        loop do
          chunk = io.readpartial(4096)
          buffer << chunk if buffer.bytesize < MAX_PROCESS_OUTPUT
        end
      rescue EOFError, IOError
        buffer
      end

      def stop_process_group(pid, term_grace: 0.25, kill_grace: 2.0)
        group = Integer(pid)
        return false unless group.positive?
        return false if group == Process.getpgrp
        return true unless process_group_alive?(group)

        signal_group("TERM", group)
        return true if wait_for_group_exit(group, term_grace)

        signal_group("KILL", group)
        wait_for_group_exit(group, kill_grace)
      rescue ArgumentError, TypeError
        false
      end

      def signal_group(signal, group)
        Process.kill(signal, -group)
        true
      rescue Errno::ESRCH
        true
      rescue Errno::EPERM
        false
      end

      def wait_for_group_exit(group, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          return true unless process_group_alive?(group)
          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.025
        end
      end

      def process_group_alive?(group)
        Process.kill(0, -group)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def kill_owned_child(wait_thr)
        return false unless wait_thr.alive?

        Process.kill("KILL", wait_thr.pid)
        true
      rescue Errno::ESRCH
        true
      rescue Errno::EPERM
        false
      end

      def command_deadline(limit)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        plan_remaining = begin
          @plan.deadline_at ? Time.iso8601(@plan.deadline_at) - Time.now : limit
        rescue StandardError
          limit
        end
        now + [[limit, plan_remaining].min, 0].max
      end

      def deadline_remaining(deadline)
        deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
