# frozen_string_literal: true

require "rbconfig"
require_relative "../../master/lib/io/exec"

module Law
  # One adapter to the canonical pub5 check registry. The individual check
  # remains the source of its assertion; this adapter only invokes it and
  # preserves the runner's four outcomes.
  module CheckRunner
    ROOT = Core::ROOT
    RUNNER = File.join(ROOT, "master", "checks", "runner.rb")
    TIMEOUT = 1_800
    Result = Data.define(:status, :output, :exit_code)

    module_function

    def run(name, timeout: TIMEOUT)
      raise ArgumentError, "unknown check id" unless name.is_a?(String) && /\A[a-z][a-z0-9_]*\z/.match?(name)
      raise LoadError, "pub5 check runner is missing" unless File.file?(RUNNER)

      output, process = Master::Io::Exec.capture2e(
        RbConfig.ruby, RUNNER, name, chdir: ROOT, timeout:, raise_on_timeout: true
      )
      exit_code = process.exitstatus
      Result.new(status: classify_exit(exit_code), output: output.to_s, exit_code:)
    rescue Master::Io::Exec::TimeoutError => e
      Result.new(status: :error, output: "check #{name} timed out after #{timeout}s: #{e.message}", exit_code: nil)
    rescue StandardError => e
      Result.new(status: :error, output: "#{e.class}: #{e.message}", exit_code: nil)
    end

    def classify_exit(exit_code)
      case exit_code
      when 0 then :passed
      when 3 then :inconclusive
      else :failed
      end
    end
  end
end
