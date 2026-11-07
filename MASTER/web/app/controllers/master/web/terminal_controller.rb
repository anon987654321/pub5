module Master
  module Web
    class TerminalController < ApplicationController
      layout "master_web"

      def index
        @boot_timestamp = Time.now.strftime("%b %e %T")
        @dmesg_header = "OpenBSD 7.6-current (GENERIC) master_web0 active"
      end

      def execute
        command = params[:command]
        output = Master::Shell.execute_command(command)

        render json: {
          command: command,
          output: output,
          prompt: Master::Shell.build_openbsd_prompt(0)
        }
      end
    end
  end
end
