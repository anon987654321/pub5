# frozen_string_literal: true

module Master
  module CLI
    class Session
      private

      def toggle_focus
        @focus_mode = !@focus_mode
        Master::Trace::Dmesg.status("focus0", @focus_mode ? "on" : "off")
      end
    end
  end
end
