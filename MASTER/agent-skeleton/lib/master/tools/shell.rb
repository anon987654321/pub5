# frozen_string_literal: true

require "open3"

module Master
  module Tools
    # Run a shell command and capture stdout/stderr/exit code.
    # NOTE: acceptable on your own machine for trusted use. Before exposing
    # MASTER to untrusted input, wrap execution in a container (Docker,
    # gVisor) — sandboxing is orthogonal to the Ruby code.
    class Shell < Tool
      def name
        "shell"
      end

      def description
        "Execute a shell command and return stdout, stderr and the exit code. " \
          "Use for scripts, file inspection and system tasks."
      end

      def parameters
        {
          type: "object",
          properties: {
            command: { type: "string", description: "The shell command to run" },
            timeout_s: { type: "integer", description: "Kill the command after this many seconds" }
          },
          required: ["command"]
        }
      end

      def call(args)
        cmd = args.fetch("command")
        timeout = args.fetch("timeout_s", 30).to_i.clamp(1, 300)

        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          out_t = Thread.new { stdout.read }
          err_t = Thread.new { stderr.read }

          if wait_thr.join(timeout).nil?
            Process.kill("KILL", wait_thr.pid) rescue nil
            return { error: "timeout after #{timeout}s", command: cmd }
          end

          { exit_code: wait_thr.value.exitstatus,
            stdout: clip(out_t.value),
            stderr: clip(err_t.value) }
        end
      end

      private

      def clip(str, n = 8000)
        str = str.to_s
        str.length > n ? str[0, n] + "\n...[truncated]" : str
      end
    end
  end
end
