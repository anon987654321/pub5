# frozen_string_literal: true

module Master
  module CLI
    # The REPL's terminal: help, line reading, completion, history, exit,
    # multiline input and the first-boot screens.
    class Session
      QUICK_COMMAND_COMPLETIONS = %w[/fix /status /doctor /model /session /help].freeze

      private

      # Terminal output and prompt editing share one protocol. Dmesg owns
      # the lock; this boundary keeps Reline's draft-safe redraw beside the
      # ordinary terminal writers used by every session lane.

      # All operator-facing writes share Dmesg's mutex and the draft guard.
      # A background event replaces the transient prompt row, then Reline
      # redraws the editable line beneath it. Advancing before the event left
      # an empty row between every pair of background messages. Writes that
      # belong to the draft machinery — spinner, activity row and read-end
      # bookkeeping — pass guard: false and manage their rows alone.
      def terminal_write(io: $stdout, guard: true, &block)
        Master::Trace::Dmesg.terminal_write(io:, guard:, &block)
      end

      # A write target may be any IO-like log; only a live terminal answers
      # tty?. The rescue is the boundary check: a writer without tty? is not
      # a terminal, not an error.
      def tty_target?(target)
        !!target.tty?
      rescue NoMethodError
        false
      end

      # Called under Dmesg's mutex, before the payload. The prompt is a
      # redrawable draft, not a permanent row: clear it in place, let the
      # payload occupy that row, then redraw the draft beneath the message.
      # Do not emit CRLF here; it creates a blank row before every later event.
      def foreign_write_begin(target)
        return unless tty_target?(target)

        if @reading_input
          clear_reserved_activity_row(target) if @activity_row_reserved
          target.print("\r\e[K")
        elsif @spinner_row_visible
          # A queued turn paints the star on the current blank row. Clear only
          # that row before a log event writes there; never move the cursor.
          target.print("\r\e[K")
          @spinner_row_visible = false
        end
      end

      # Called under Dmesg's mutex, after the payload. Reline's differential
      # render only repaints rows that differ from its cache, and a foreign
      # write is invisible to it — so the cache must be reset for the next
      # redisplay to be a full repaint, anchored at the cursor, the row where
      # the payload just ended.
      def foreign_write_end(target)
        return unless @reading_input && tty_target?(target)

        # Do not print a blank spinner row after every dmesg event. The spinner
        # reclaims one row only after the event stream has been quiet briefly.
        @last_foreign_write_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        redraw_active_input
      end

      def redraw_active_input
        refresh_reline_screen_cache!
        Reline.redisplay
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.reline.redisplay", event_bus: @refs.bus)
      end

      # :reek:ManualDispatch -- Reline 0.7 has no public full-repaint reset;
      # the private cache clear is the one boundary, and a responds-guard keeps
      # a foreign redraw a no-op if the gem's shape changes.
      #
      # Reline 0.7 keeps the rendered-line cache on its line editor as
      # @rendered_screen, reset by the private clear_rendered_screen_cache
      # (lines and cursor_y). Reaching it is deliberate: the cache is the one
      # source of Reline's differential silence.
      def refresh_reline_screen_cache!
        editor = Reline.line_editor
        editor.send(:clear_rendered_screen_cache) if editor.respond_to?(:clear_rendered_screen_cache, true)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.reline.cache", event_bus: @refs.bus)
      end

      # The splash is the last of the boot, so it keeps the boot's console colours.
      def print_splash
        terminal_puts(Master::Trace::Dmesg.console_paint(@refs.renderer.splash(@refs.agent.model), $stdout))
      end

      def terminal_puts(text = "", io: $stdout, guard: true)
        terminal_write(io:, guard:) { |target| target.puts(text); target.flush }
      end

      def terminal_print(text, io: $stdout, guard: true)
        terminal_write(io:, guard:) { |target| target.print(text); target.flush }
      end


      def run_help(command = nil)
        arg = command.to_s.strip
        text = arg.empty? ? Master::CLI::CommandRegistry.help_summary : Master::CLI::CommandRegistry.help_text(arg)

        print_terminal_output(text, mode: :dim)
        Master::Result.ok(text)
      end

      # Long command results are easier to inspect in a pager, but piping MASTER
      # or running it on a phone must stay plain and non-interactive. Only the
      # two known pager binaries are accepted; arbitrary PAGER shell commands
      # would turn a display convenience into command execution.
      def print_terminal_output(text, mode: :dim)
        rendered = @refs.renderer.render(text.to_s, mode:)
        return if rendered.empty?
        return if pageable_output?(rendered) && page_terminal_output(rendered)

        terminal_puts(rendered)
      end

      def display_prepared_terminal_output(text)
        return if text.to_s.empty?
        return if pageable_output?(text) && page_terminal_output(text)

        terminal_puts(text)
      end

      def pageable_output?(text)
        return false unless $stdout.tty?
        return false if %w[0 off no false].include?(ENV["MASTER_PAGER"].to_s.downcase)

        height = TTY::Screen.height.to_i
        text.to_s.lines.count >= [height - 2, 12].max
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.pager.height", event_bus: @refs.bus)
        false
      end

      def page_terminal_output(text)
        command = terminal_pager_command
        return false unless command

        IO.popen(command, "w") do |pager|
          begin
            pager.write(text)
            pager.flush
          rescue Errno::EPIPE
            # The operator quit before reading all of the buffer. Do not dump it
            # again to the terminal after returning from the pager.
          end
        end
        true
      rescue Errno::ENOENT, Errno::EACCES => e
        Master::Ground::Swallow.log(e, context: "cli.pager.start", event_bus: @refs.bus)
        false
      end

      def terminal_pager_command
        selected = ENV.fetch("MASTER_PAGER", "auto").strip.downcase
        return if %w[0 off no false].include?(selected)

        candidates = case selected
                     when "auto" then %w[less more]
                     when "less", "more" then [selected]
                     else
                       Master::Trace::Dmesg.status("pager0", "unsupported MASTER_PAGER value; use auto, less, more or 0")
                       return
                     end

        candidates.each do |name|
          executable = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
            .find { |candidate| File.file?(candidate) && File.executable?(candidate) }
          next unless executable

          return name == "less" ? [executable, "-FRX"] : [executable]
        end
        nil
      end

      # Reline asks the terminal where the cursor is, and a reply that arrives
      # late lands in the input as text, "[38;51R", which would be saved and
      # replayed as the operator's words. A paste the terminal did not bracket
      # arrives as lines already waiting, and those join the first rather than
      # becoming prompts of their own.
      TERMINAL_REPLY = /\e?\[?\d{1,4};\d{1,4}R|\e\[[\d;?]*[A-Za-z~]/

      def safe_read_line(prompt = "")
        line = Reline.readline(prompt, false)
        return if line.nil?

        line = [line, *pasted_lines].join("\n")
        clean = line.gsub(TERMINAL_REPLY, "").chomp
        Reline::HISTORY << clean unless clean.strip.empty?
        clean
      rescue IOError, Errno::EIO => e
        Master::Ground::Swallow.log(e, context: "cli.safe_read_line", event_bus: @refs.bus)
        Master::Trace::Dmesg.status("input0", "terminal unavailable, closing")
        nil
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.safe_read_line", event_bus: @refs.bus)
        Master::Trace::Dmesg.status("input0", "read failed, #{e.class}; retrying")
        :interrupted
      end

      def pasted_lines
        lines = []
        lines << Reline.readline("", false).to_s while lines.size < MULTILINE_MAX_LINES && Reline::IOGate.in_pasting?
        lines
      end

      def setup_completion
        Reline.completion_proc = proc do |target|
          line = Reline.line_buffer.to_s
          command = line.split.first.to_s.downcase

          if line.match?(%r{\A/\S+\s+}) && SLASH_COMMANDS.include?(command)
            complete_command_argument(line, target)
          elsif line.match?(%r{\A/\S*\z})
            SLASH_COMMANDS.select { |cmd| cmd.start_with?(target.to_s) }
          elsif line.strip.empty?
            QUICK_COMMAND_COMPLETIONS.map { |cmd| "#{cmd} " }
          else
            []
          end
        end
      end

      def complete_command_argument(line, target)
        command = line.split.first.to_s
        case command
        when "/model"
          model_completion(target)
        when "/help"
          SLASH_COMMANDS.map { |name| name.delete_prefix("/") }.select { |name| name.start_with?(target.to_s) }
        else
          complete_paths(target)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.complete_argument")
        []
      end

      def model_completion(target)
        pool = @refs.agent.respond_to?(:model_router) && @refs.agent.model_router
        models = pool&.pool(wait: false)
        Array(models).map(&:to_s).select { |model| model.start_with?(target.to_s) }.first(50)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.complete_model")
        []
      end

      def complete_paths(target)
        prefix = target.to_s.empty? ? "*" : "#{target}*"
        Dir.glob(File.join(@refs.root, prefix)).map do |path|
          rel = path.delete_prefix("#{@refs.root}/")
          File.directory?(path) ? "#{rel}/" : rel
        end.first(50)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.complete_paths")
        []
      end

      def cli_history_path
        File.join(@refs.root, ".master", "cli_history")
      end

      def load_cli_history
        path = cli_history_path
        return unless File.exist?(path)

        File.readlines(path, chomp: true).last(HISTORY_LIMIT).each { |line| Reline::HISTORY << line unless line.empty? }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.load_history", event_bus: @refs.bus)
      end

      def save_cli_history
        path = cli_history_path
        FileUtils.mkdir_p(File.dirname(path))
        # Every prompt the operator typed: owner-only, as the shell keeps its own history.
        File.write(path, Reline::HISTORY.to_a.last(HISTORY_LIMIT).join("\n") + "\n", perm: 0o600)
        File.chmod(0o600, path)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.save_history", event_bus: @refs.bus)
      end

      def exit_cli
        @running = false
        if $stdin.tty? && $stdout.tty?
          pending = interactive_queue_count
          # A backlog the operator typed is work they meant done; the exit
          # receipt names what closing drops instead of silently clearing it.
          terminal_puts("queue0: /exit discards #{pending} queued message#{pending == 1 ? "" : "s"}") if pending.positive?
        end
        shutdown_interactive_queue! if $stdin.tty? && $stdout.tty?
        line = @refs.renderer.closing
        terminal_puts(line) if line
        close_session
      end

      def save_session_on_exit
        @refs.session&.save!
      rescue StandardError => e
        Master::Trace::Dmesg.status(
          "session0", "save failed - #{e.class}: #{e.message}", io: $stderr
        )
      end

      def read_multiline
        lines = []
        Master::Trace::Dmesg.status("input0", "enter lines, blank line to send")
        loop do
          inner = safe_read_line("  ")
          break if inner.nil? || inner.strip.empty?
          lines << inner
          if lines.size >= MULTILINE_MAX_LINES
            Master::Trace::Dmesg.status("cli0", "multiline capped at #{MULTILINE_MAX_LINES} lines")
            break
          end
        end
        lines.join("\n")
      end

      def print_quick_start
        return unless $stdin.tty? && $stdout.tty?

        Master::Trace::Dmesg.status(
          "input0",
          "describe the task in plain language; Tab shows common commands; /help lists the full surface",
        )
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.quick_start", event_bus: @refs.bus)
      end

      def print_repo_tree
        lines = Master::CLI::CommandRegistry.dispatch_tree(@refs.root).to_s.split("\n")
        return if lines.empty?

        # One line, as a disk attaches: the entries are `/tree` away, and two
        # hundred of them buried the prompt on a first boot.
        Master::Trace::Dmesg.status("tree0", "#{File.basename(@refs.root)}, #{lines.size} entries")
        mark_booted
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_repo_tree", event_bus: @refs.bus)
      end

      def booted_before?
        flag = File.join(@refs.root, ".master", "booted_once")
        File.exist?(flag)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.booted_before?", event_bus: @refs.bus)
        false
      end

      def skip_boot_scan?
        ENV["MASTER_SKIP_BOOT_SCAN"] == "1" || ENV["MASTER_PIPE"] == "1"
      end

      # A prompt is ready when the session is ready. Repository-wide observation
      # belongs to an explicit /fix request; continuous observation is
      # an opt-in diagnostic for an operator who asks for it.
      def background_scan_enabled?
        ENV["MASTER_BACKGROUND_SCAN"] == "1" && !skip_boot_scan?
      end

      def mark_booted
        flag = File.join(@refs.root, ".master", "booted_once")
        FileUtils.mkdir_p(File.dirname(flag))
        File.write(flag, Time.now.to_s)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.mark_booted", event_bus: @refs.bus)
      end
    end
  end
end
