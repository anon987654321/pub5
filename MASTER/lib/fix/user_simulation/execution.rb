# frozen_string_literal: true

module Master
  module Fix
    class UserSimulation
      # Execution surface: focused-test selection into commands, bounded test
      # runs, baseline/candidate comparison and the reversible source
      # transaction around each candidate trial. The defining file is
      # fix/best_of_n.rb; this re-opens its UserSimulation class.


      private

      def execute_test(test_path)
        timeout = timeout_for_next_test
        return { path: test_path, state: :blocked, signature: "file-budget", detail: "insufficient file budget for focused test" } unless timeout
        return normalize_runner_result(test_path, @runner.call(test_path)) if @runner

        root, command, kind = command_for(test_path)
        return { path: test_path, state: :blocked, signature: "unsupported-test-path", detail: "unsupported test path" } unless root && command

        if kind == :rails
          env = Master::Fix::RailsApp.env(root).merge("RAILS_ENV" => "test")
          run = -> { Master::Io::Exec.capture2e(env, *command, chdir: root, timeout:, raise_on_timeout: true) }
          output, status = defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
        elsif kind == :ruby
          env = Master::Fix::RailsApp.env(root)
          output, status = Master::Io::Exec.capture2e(env, *command, chdir: root, timeout:, raise_on_timeout: true)
        else
          output, status = Master::Io::Exec.capture2e(*command, chdir: root, timeout:, raise_on_timeout: true)
        end
        normalize_runner_result(test_path, [output, status])
      rescue Master::Io::Exec::TimeoutError => e
        { path: test_path, state: :timeout, signature: Digest::SHA256.hexdigest(e.message)[0, 16], detail: e.message[0, 160] }
      rescue StandardError => e
        { path: test_path, state: :blocked, signature: Digest::SHA256.hexdigest("#{e.class}:#{e.message}")[0, 16], detail: "#{e.class}: #{e.message}"[0, 160] }
      end

      def command_for(test_path)
        master_test_command(test_path) || master_web_test_command(test_path) ||
          rails_test_command(test_path) || rails_app_test_command(test_path)
      end

      def master_test_command(test_path)
        return nil unless test_path.start_with?("MASTER/test/")

        root = File.join(@root, "MASTER")
        [root, ["bundle", "exec", "ruby", "-Itest", test_path.delete_prefix("MASTER/")], :ruby]
      end

      def master_web_test_command(test_path)
        return nil unless test_path.start_with?("MASTER/web/")

        root = File.join(@root, "MASTER", "web")
        relative = test_path.delete_prefix("MASTER/web/")
        return [root, ["node", "--test", relative], :process] if relative.end_with?(".mjs")

        [root, ["bin/rails", "test", relative], :rails]
      end

      def rails_test_command(test_path)
        return nil unless test_path.start_with?("RAILS/test/")

        root = File.join(@root, "RAILS")
        relative = test_path.delete_prefix("RAILS/")
        return [root, ["node", "--test", relative], :process] if relative.end_with?(".mjs")
        return [root, ["ruby", relative], :ruby] if relative.end_with?(".rb")

        nil
      end

      def rails_app_test_command(test_path)
        match = test_path.match(%r{\ARAILS/(brgen|amber|bsdports)/})
        return nil unless match

        root = File.join(@root, "RAILS", match[1])
        relative = test_path.delete_prefix("RAILS/#{match[1]}/")
        [root, ["bin/rails", "test", relative], :rails]
      end

      def normalize_runner_result(test_path, raw)
        if raw.is_a?(Hash)
          row = raw.transform_keys(&:to_sym)
          state = row.fetch(:state).to_sym
          signature = row[:signature].to_s
          return { path: test_path, state:, signature:, detail: row[:detail].to_s[0, 160] }
        end

        output, status = raw
        state = status && status.success? ? :pass : :fail
        summary = failure_summary(output)
        signature = state == :pass ? "PASS" : Digest::SHA256.hexdigest(summary)[0, 16]
        { path: test_path, state:, signature:, detail: state == :pass ? "" : summary[0, 160] }
      end

      def failure_summary(output)
        text = output.to_s.gsub(@root, "<repo>")
          .gsub(%r{(?:/private)?/tmp/[^\s:]+}, "<tmp>")
        lines = text.lines.map(&:strip).reject(&:empty?)
        marked = lines.select do |line|
          line.match?(/\A(?:Failure|Error|ERROR|FAIL|not ok\b|# fail\b|# error\b|\d+ runs?,|\d+ examples?,|\d+ tests?,)/i)
        end
        (marked.empty? ? lines.last(12) : marked.last(24)).join("\n")
      end

      def compare(baseline, candidate, tests)
        regressions = comparison_regressions(tests, baseline, candidate)
        improvements = comparison_improvements(tests, baseline, candidate)
        status = comparison_status(candidate, regressions, improvements)
        result(status, tests, baseline, candidate, regressions:, improvements:)
      end

      def comparison_regressions(tests, baseline, candidate)
        tests.each_with_index.filter_map do |test_path, index|
          before = baseline[index]
          after = candidate[index]
          if before[:state] == :pass && after[:state] != :pass
            "#{test_path}: baseline passed, candidate #{after[:state]}"
          elsif before[:state] != :pass && after[:state] != :pass &&
                (before[:state] != after[:state] || before[:signature] != after[:signature])
            "#{test_path}: candidate changes an existing failure signature"
          end
        end
      end

      def comparison_improvements(tests, baseline, candidate)
        tests.each_with_index.filter_map do |test_path, index|
          before = baseline[index]
          after = candidate[index]
          next unless before[:state] != :pass && after[:state] == :pass

          "#{test_path}: candidate passes a previously failing/blocked baseline"
        end
      end

      def comparison_status(candidate, regressions, improvements)
        if regressions.any?
          :regression
        elsif candidate.all? { |row| row[:state] == :pass }
          :pass
        elsif candidate.any? { |row| %i[blocked timeout].include?(row[:state]) }
          :blocked
        elsif improvements.any?
          :improved
        else
          :no_regression
        end
      end

      def result(status, tests, baseline, candidate, regressions: [], improvements: [], reason: nil)
        {
          status:,
          test_paths: tests,
          baseline:,
          candidate:,
          regressions:,
          improvements:,
          reason:,
        }
      end

      def result_rows(sources, status, reason)
        Array(sources).map do |_source|
          result(status, [], [], [], reason:)
        end
      end

      def verify_unchanged_source!(path, original, relative, phase)
        actual = File.read(path, encoding: "UTF-8")
        return true if actual == original

        publish(
          "repair_loop:user_simulation_blocked",
          path: relative,
          phase:,
          reason: "source changed outside the candidate transaction; preserving current content",
        )
        raise RestoreFailure, "source changed during #{phase}; refusing candidate selection for #{relative}"
      end

      def test_timeout
        Integer(ENV.fetch("MASTER_FIX_SIMULATION_TEST_TIMEOUT_S", DEFAULT_TIMEOUT_S.to_s)).clamp(MIN_TEST_TIMEOUT_S, 300)
      rescue ArgumentError
        DEFAULT_TIMEOUT_S
      end

      def budget_block_reason
        return unless @deadline

        remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        required = @commands_remaining * MIN_TEST_TIMEOUT_S + POST_SIMULATION_RESERVE_S
        return if remaining >= required

        "file budget cannot reserve #{POST_SIMULATION_RESERVE_S}s for final verification plus #{MIN_TEST_TIMEOUT_S}s for each of #{@commands_remaining} focused test commands"
      end

      def timeout_for_next_test
        commands = [@commands_remaining.to_i, 1].max
        @commands_remaining = [commands - 1, 0].max
        return @timeout unless @deadline

        remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        available = remaining - POST_SIMULATION_RESERVE_S
        return if available < MIN_TEST_TIMEOUT_S * commands

        [@timeout, (available / commands).floor].min
      end

      def with_simulation_lock
        lock_path = File.join(@root, "MASTER", ".master", "candidate-simulation.lock")
        FileUtils.mkdir_p(File.dirname(lock_path))
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          begin
            yield
          ensure
            lock.flock(File::LOCK_UN)
          end
        end
      end

      def publish(event, payload = {}, **keywords)
        @bus&.publish(event, payload.merge(keywords))
      rescue StandardError
        nil
      end

      def reason(error)
        message = error.message.to_s
          .gsub(@root, "<repo>")
          .gsub(/((?:api[_-]?key|access[_-]?token|password|secret|authorization)\s*[=:]\s*)\S+/i, "\\1<redacted>")
          .gsub(/\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|github_pat_[A-Za-z0-9_]{8,})\b/, "<redacted>")
        "#{error.class}: #{message}"[0, 180]
      end
    end
  end
end
