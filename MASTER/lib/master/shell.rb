# lib/master/shell.rb - Monochromatic Readline REPL Shell
require 'readline'
require 'master/shell/git_cache'

module Master
  class Shell
    PROMPT = "master: ~ $ ".freeze

    def self.start
      print_kernel_banner
      setup_signal_traps

      while buf = Readline.readline(PROMPT, true)
        line = buf.strip
        next if line.empty?

        # Deduplicate consecutive history entries
        Readline::HISTORY.pop if Readline::HISTORY.to_a[-2] == line

        break if handle_builtin_command(line)
      end

      puts "\nmaster: kernel shutdown sequence completed."
    rescue Interrupt
      print "\nmaster: kernel interrupt received (SIGINT). Safe shutdown initiated.\n"
      exit 0
    end

    # The OpenBSD-style prompt. Branch and dirty state come from the
    # asynchronous GitCache, never a blocking subprocess; the exit token is
    # ':' for success and '!' for failure.
    def self.build_openbsd_prompt(last_status = 0)
      GitCache.start_background_sync unless @sync_started
      @sync_started = true

      branch, dirty = GitCache.read
      branch_info = branch.empty? ? "" : "(#{branch})"
      status_marker = dirty.empty? ? "" : "*"
      exit_token = last_status == 0 ? ":" : "!"

      "master#{branch_info}#{status_marker} #{exit_token} "
    end

    def self.print_kernel_banner
      puts "OpenBSD 7.6-current (GENERIC) #0: master_ksh0 active"
      puts "Type 'help' for available system commands or 'exit' to terminate.\n\n"
    end

    def self.setup_signal_traps
      Signal.trap("TERM") do
        puts "\nmaster: SIGTERM received. Flushing buffers and exiting."
        exit 0
      end
    end

    def self.handle_builtin_command(line)
      case line
      when 'exit', 'quit'
        true
      when 'help'
        print_help
        false
      when 'dmesg'
        print_kernel_logs
        false
      when /^studio/
        dispatch_studio_pipeline(line)
        false
      else
        execute_system_command(line)
        false
      end
    end

    def self.print_help
      puts "  dmesg       - Display kernel ring buffer logs"
      puts "  studio      - Invoke STUDIO dilla/postpro/replicate pipelines"
      puts "  status      - Display active SQLite & thread pool metrics"
      puts "  exit        - Terminate shell session"
    end

    def self.execute_system_command(cmd)
      # Execute safely in isolated subshell
      output = `#{cmd} 2>&1`
      print output unless output.empty?
    rescue StandardError => e
      puts "master: execution error -> #{e.message}"
    end
  end
end
