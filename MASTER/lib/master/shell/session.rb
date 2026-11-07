require 'readline'

module Master
  class Shell
    class Session
      def self.initialize_terminal!
        # Graceful SIGINT / SIGTERM handling
        trap("INT") do
          print "\nmaster: [Nov  7 06:56:10] kernel shutdown sequence initiated...\n"
          exit 0
        end

        trap("TERM") do
          exit 0
        end

        # Readline completion caching dictionary
        completion_commands = ['help', 'exit', '/scrape', '/audio', '/grants', '/fix', '/status']
        Readline.completion_proc = proc do |str|
          @completion_cache ||= completion_commands
          @completion_cache.grep(/^#{Regexp.escape(str)}/)
        end
      end
    end
  end
end
