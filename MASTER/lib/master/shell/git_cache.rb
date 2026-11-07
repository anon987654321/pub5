require 'thread'

module Master
  class Shell
    class GitCache
      @mutex = Mutex.new
      @branch = ""
      @dirty = ""
      @running = false

      def self.start_background_sync
        return if @running
        @running = true

        Thread.new do
          loop do
            b = `git branch --show-current 2>/dev/null`.strip
            d = `git status --porcelain 2>/dev/null`.strip

            @mutex.synchronize do
              @branch = b
              @dirty = d
            end

            sleep 2 # Poll repo state every 2 seconds in background
          end
        end
      end

      def self.read
        @mutex.synchronize { [@branch, @dirty] }
      end
    end
  end
end
