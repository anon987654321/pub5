# frozen_string_literal: true

module Master
  module Web
    # The operator's web terminal. This controller only renders the page:
    # public/master_terminal.js sends each line to ChatController#command, the
    # one authenticated CLI channel (gateway, rate limit, same-origin check),
    # so nothing here runs a command.
    class TerminalController < ApplicationController
      layout "master_web"

      skip_before_action :require_container!
      before_action :require_authenticated!

      def index
        @dmesg_header = "master_web0 at ttyWeb0: #{Master::VERSION}"
      end
    end
  end
end
