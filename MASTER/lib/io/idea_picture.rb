# frozen_string_literal: true

require "json"
require "rbconfig"
require_relative "exec"

module Master
  module Io
    # MASTER-facing adapter for STUDIO photograph and LoRA work. MASTER owns
    # routing and result contracts; STUDIO owns provider calls and media files.
    class IdeaPicture
      SCRIPT = File.expand_path("../../../STUDIO/lora/photograph.rb", __dir__)

      def initialize(script: SCRIPT)
        @script = script
      end

      def validate_model(subject:, timeout: Master::Io::Exec::DEFAULT_TIMEOUT)
        argv = [RbConfig.ruby, @script, "--check-model", "--subject", subject.to_s]
        run(argv, timeout:, action: "STUDIO LoRA preflight")
      end

      def write(words, film: true, duration: 5, subject: nil, timeout: Master::Io::Exec::DEFAULT_TIMEOUT)
        argv = [RbConfig.ruby, @script]
        argv += ["--subject", subject.to_s] unless subject.to_s.empty?
        argv << "--film" if film
        argv += ["--duration", duration.to_i.to_s, words.to_s]
        run(argv, timeout:, action: "STUDIO photograph")
      end

      def animate(source, prompt:, subject:, duration: 5, timeout: Master::Io::Exec::DEFAULT_TIMEOUT)
        argv = [
          RbConfig.ruby, @script, "--animate", source.to_s,
          "--subject", subject.to_s, "--duration", duration.to_i.to_s,
          "--prompt", prompt.to_s,
        ]
        run(argv, timeout:, action: "STUDIO LoRA animation")
      end

      def selfie_series(subject:, count: 10, replace: false, timeout: 7_200)
        argv = [
          RbConfig.ruby, @script, "--selfie-series", "--subject", subject.to_s,
          "--count", Integer(count).to_s,
        ]
        argv << "--replace" if replace
        run(argv, timeout:, action: "STUDIO LoRA selfie series")
      end

      private

      def run(argv, timeout:, action:)
        raise "#{action} entrypoint is unavailable" unless File.file?(@script)

        stdout, status = Master::Io::Exec.capture2e(
          *argv, chdir: File.dirname(@script), timeout:, raise_on_timeout: true
        )
        raise "#{action} failed: #{stdout.lines.last.to_s.strip}" unless status.success?

        parsed = JSON.parse(stdout)
        parsed.is_a?(Hash) ? parsed.transform_keys(&:to_sym) : parsed
      rescue Master::Io::Exec::TimeoutError => error
        raise "#{action} timed out: #{error.message}"
      end
    end
  end
end
