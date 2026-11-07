module Master
  module Web
    class TerminalChannel < ApplicationCable::Channel
      def subscribed
        stream_from "master_web_terminal_session"

        transmit({
          type: "dmesg",
          content: "master: [Nov  7 07:07:15] web_client0 attached to ttyWeb0\n"
        })
      end

      def receive(data)
        command = data["command"]
        return if command.blank?

        # Execute command through Master shell dispatcher
        output = Master::Shell.execute_command(command)
        exit_status = $?.exitstatus || 0

        ActionCable.server.broadcast(
          "master_web_terminal_session",
          {
            type: "output",
            command: command,
            output: output,
            prompt: Master::Shell.build_openbsd_prompt(exit_status)
          }
        )
      end

      def unsubscribed
        # Clean up terminal session resources
      end
    end
  end
end
