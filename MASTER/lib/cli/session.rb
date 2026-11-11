# frozen_string_literal: true

require_relative "session/container"
require_relative "session/signals"
require_relative "session/command_ops"
require_relative "session/thinking_indicator"
require_relative "activity"
require_relative "session/result_display"
require_relative "session/background_scan"
require_relative "session/reminders"
require_relative "session/repl_flow"
require_relative "session/greeting"
require_relative "session/bridge_run"
require_relative "operator_grammar"

require "open3"
require "reline"
require "tty-prompt"
require "tty-screen"
require "fileutils"

module Master
  module CLI
    class Session
      CONFIG = Master.patterns_config.fetch("cli", {}).freeze
      IDLE_SLEEP_DEFAULT = CONFIG.fetch("idle_sleep_seconds", 60)
      DMESG_BUFFER_LINES = CONFIG.fetch("dmesg_buffer_lines", 80)
      MULTILINE_MAX_LINES = CONFIG.fetch("multiline_max_lines", 500)
      HISTORY_LIMIT = CONFIG.fetch("history_limit", 2_000)
      ERROR_TEXT_MAX_CHARS = 200
      ROUTINE_SUCCESS_MAX_LENGTH = 120

      SEVERITY_ICON = {
        error: "!!",
        warning: "!",
        style: ".",
        critical: "!!",
      }.freeze
      SLASH_COMMANDS = CommandRegistry.slash_commands.freeze

      attr_reader :container
      attr_reader :exit_code

      def initialize(container:)
        @container = container
        Fiber[:master_cli_container] = container
        @refs = Container.from_hash(container)
        Reline::HISTORY.clear
        load_cli_history
        setup_completion
        init_session_state!
        # One registration of the draft guard, so every operator-facing write
        # from every lane shares the same protocol with Reline's editable line.
        Master::Trace::Dmesg.draft_guard = [method(:foreign_write_begin), method(:foreign_write_end)]
        # One live Reline prompt; the face is the web particle face only.
        Fiber[:master_cli_prompt] = -> { @focus_mode ? focus_prompt : normal_prompt }
        set_visitor_mode_if_unauthenticated
      end

      def run(initial_message = nil)
        setup_signals
        @refs.agent.pin_boot_model! if @refs.agent.respond_to?(:pin_boot_model!)
        @refs.session.load! if @refs.session.exists?
        start_background_loop if background_scan_enabled?
        # One vertical rhythm: the dmesg, a blank line, the ready block, then
        # a blank line before each block that follows and before the prompt.
        print_splash
        # One line for a resumed session. Replaying its last turns printed an old
        # reply above the prompt, which read as a canned answer to a message not
        # yet typed.
        terminal_puts(@refs.renderer.session_line(@refs.session.messages.size)) if @refs.session.name
        unless booted_before?
          print_repo_tree
          print_quick_start
        end
        run_input(initial_message) if initial_message
        greet_from_model unless initial_message
        @running = true
        play_boot_sound
        # The face is the web particle face only (Johann 2026-11-07): the
        # terminal paints no ASCII face, and the /face verb is retired with it.
        start_boot_scan if background_scan_enabled?
        start_reminder_watch
        repl_loop
      end

      def pipe(input)
        stripped = input.strip
        return empty_input(:pipe) if stripped.empty?

        handle_repl_line(stripped)
      end

      # bin/master's fast one-shot (-p with a tty) queues the line through the
      # interactive queue and is about to exit; nothing else would join the
      # worker, so the turn died mid-flight - the operator saw "queue0: run:"
      # and no answer, and the process left 0 whatever the turn decided
      # (reproduced with a raw PTY boot on this checkout, 2026-11-08). The
      # process that queued a turn owes the operator its answer before it
      # leaves: join the worker until the queue is drained, and the exit code
      # is the turn's own.
      def drain_pending_turns!
        loop do
          worker = @turn_queue_mutex.synchronize { @turn_worker }
          break if worker.nil?

          worker.join
        end
        @exit_code
      end

      def run_input(input)
        return empty_input(:run_input) if input.strip.empty?
        @turn_queue_mutex.synchronize { @turn_cancel_requested = false unless @turn_queue_paused }
        return Master::Result.err("turn cancelled before start", category: :abort) if turn_cancel_requested?
        blocked = check_budget_blocks(input)
        return blocked if blocked

        @refs.ground_truth&.begin_turn! if @refs.respond_to?(:ground_truth)
        @user_active = true
        @last_input = input
        Master::Trace::WriteTracker.current&.reset!
        paste, state, accumulated = init_turn_state(input)

        print_thinking_indicator unless paste
        result = dispatch_turn(input, accumulated:, state:)
        stop_thinking_indicator
        print_bridge_footer(result.value[:core], state:) if result.ok? && state[:streamed] && result.value[:core]
        display_result(result:, accumulated:, streamed: state[:streamed], units_console: state[:units_console])
        @last_repeatable_input = input if result.ok? && Master::Io::MediaIntent.repeatable?(input)

        result
      ensure
        @pipeline_thread = nil
        @turn_cancellation = nil
        stop_thinking_indicator
        close_unit_console
        @user_active = false
      end

      private

      # All operator-facing writes share Dmesg's mutex and Dmesg runs the draft
      # guard this session registers: a write from any lane clears the draft's
      # row, claims a row of its own below the cursor, and the redisplay
      # afterwards rebuilds the editable line — zsh's own rule. Before this
      # guard, a write that shared the draft's row printed its text after the
      # prompt glyphs ("master$ Welcome back."), and one that cleared it left
      # the prompt gone, because Reline's differential render repaints nothing
      # its cache still matches (the disappearing prompt after the first
      # message). Writes that are part of the draft's own machinery — the
      # spinner row, the reserved activity row, the read-end bookkeeping — pass
      # guard: false and manage their rows alone.
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

      # Called under Dmesg's mutex, before the payload. The reserved activity
      # row is given up, the draft's row is cleared and the cursor steps to a
      # fresh row below it: the payload never mixes with the prompt glyphs and
      # never lands on the row Reline is editing.
      def foreign_write_begin(target)
        return unless @reading_input && tty_target?(target)

        clear_reserved_activity_row(target) if @activity_row_reserved
        target.print("\r\e[K\r\n")
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

      def play_boot_sound
        Master::Voice::BootSound.play
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.boot_sound", event_bus: @refs.bus)
      end

      def init_session_state!
        @running = false
        @last_ok = true
        @violations = 0
        @prev_violations = 0
        @violations_mutex = Mutex.new
        @bg_thread = nil
        @bg_control = Queue.new
        @seen_violations = {}
        @user_active = false
        @focus_mode = false
        @last_input = nil
        @exit_code = 0
        @activity = Master::CLI::Activity.new
        @last_repeatable_input = nil
        @turn_queue = []
        @turn_queue_mutex = Mutex.new
        @turn_worker = nil
        @turn_current_line = nil
        @turn_current_started = false
        @turn_queue_paused = false
        @turn_cancel_requested = false
        @turn_cancellation = nil
        @reading_input = false
        @activity_row_reserved = false
        @active_prompt = nil
        @terminal_ask_mutex = Mutex.new
        @terminal_ask_cv = ConditionVariable.new
        @pending_terminal_ask = nil
        @closed = false
      end

      def init_turn_state(input)
        paste = paste_like_input?(input)
        state = { streamed: false, thinking_shown: !paste }
        accumulated = +""
        build_stream_handler(accumulated) { |text| handle_stream_text(text, state) }
        [paste, state, accumulated]
      end

      def check_budget_blocks(input)
        if (host_err = host_budget_block(input))
          return display_result(result: host_err, accumulated: "", streamed: false)
        end
        budget_err = budget_block_if_exceeded
        return display_result(result: budget_err, accumulated: "", streamed: false) if budget_err

        nil
      end

      def dispatch_turn(input, accumulated:, state:)
        return Master::Result.err("turn cancelled before dispatch", category: :abort) if turn_cancel_requested?

        on_turn = build_on_turn_handler(accumulated, state)
        @turn_cancellation = Master::Core::CancellationToken.new
        @pipeline_thread = spawn_pipeline_thread(
          input, on_turn:, on_chunk: build_on_chunk_handler(accumulated, state),
          cancellation: @turn_cancellation
        )
        request_or_interrupt_turn(@pipeline_thread, @turn_children, reason: "stop") if turn_cancel_requested? && @pipeline_thread&.alive?
        fetch_pipeline_result
      end

      def turn_cancel_requested?
        @turn_queue_mutex&.synchronize { @turn_cancel_requested == true } || false
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.queue.cancel_state", event_bus: @refs.bus)
        true
      end

      def build_on_turn_handler(accumulated, state)
        lambda do |line|
          # The units console printed this turn as it ran; the transcript line
          # would say it twice.
          next state[:streamed] = state[:units_console] = true if @unit_sub

          accumulated << line << "\n"
          handle_stream_text(line + "\n", state) if $stdout.isatty
        end
      end

      # The reply as the model writes it: the first words reach the terminal seconds before the last.
      def build_on_chunk_handler(accumulated, state)
        lambda do |chunk|
          accumulated << chunk
          handle_stream_text(chunk, state) if $stdout.isatty
        end
      end

      def spawn_pipeline_thread(input, on_turn:, on_chunk:, cancellation: nil)
        @turn_children = Master::Io::Exec::Children.new

        Thread.new do
          Thread.current.report_on_exception = false
          Fiber[:master_children] = @turn_children
          Fiber[:master_terminal_ask] = terminal_ask(Thread.current)
          TurnRouter.call(
            message: input,
            container: @container,
            felt_sense: cli_felt_sense,
            on_turn:,
            on_chunk:,
            cancellation:,
          )
        end
      end

      # Thread#value answers nil for a thread that was killed, rather than
      # raising, and signals.rb kills this one on ^C. Interrupt is not a
      # StandardError and a killed thread raises nothing, so the nil is the
      # only sign of a cancel. A turn that raised is a failure, named as one.
      def fetch_pipeline_result
        value = @pipeline_thread.value
        if value.nil?
          return Result.err("interrupted", category: :abort) if turn_cancel_requested?

          return Result.err("turn returned no result", category: :handler_exception)
        end
        return value if value.is_a?(Result)

        Result.err("turn returned invalid result: #{value.class}", category: :handler_exception)
      rescue NoMemoryError
        Result.err(host_oom_message, category: :infrastructure)
      # ScriptError too: a SyntaxError re-raised from Thread#value inherits
      # ScriptError, not StandardError — StandardError-only let one unparseable
      # file in the preflight abort the whole process instead of failing a turn.
      rescue StandardError, ScriptError => e
        Result.err("turn failed: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def empty_input(source)
        @refs.bus&.publish("cli:empty_input", source:)
        nil
      end

      def paste_like_input?(input)
        text = input.to_s
        text.lines.size > 3 || text.bytesize > 1_500
      end

      def handle_stream_text(text, state)
        if state[:thinking_shown] && $stdout.isatty
          stop_thinking_indicator
          # The inline thinking row is cleared only when nothing is being
          # edited; while the draft is live the guard moved the stream to its
          # own row and the spinner row was already the indicator's home.
          terminal_print("\r\e[K") unless @reading_input
          state[:thinking_shown] = false
        end

        # The stream claims one row below the draft, once per turn; chunks
        # grow on that row at the cursor without their own guard round-trip,
        # so a reply reads as it arrives without ever clobbering the edited
        # line. The turn's final display repaints the draft below the stream.
        if $stdout.isatty && @reading_input && !state[:stream_row_open]
          terminal_print("\r\n", guard: false)
          state[:stream_row_open] = true
        end
        terminal_print(wrap_stream(text, state), guard: false)
        state[:streamed] = true
      end

      # Preserve provider-authored text exactly. Newline insertion here becomes
      # permanent text in logs and copy/paste; the terminal handles visual wrapping.
      def wrap_stream(text, _state)
        text.to_s
      end

      def cli_felt_sense
        mood = @last_ok ? "focused" : "tense"
        mood = "curious" if @refs.session.phase == :discover
        entropy = [violations_count / 20.0, 1.0].min
        confidence = @last_ok ? 0.86 : 0.42
        { mood:, entropy: entropy.round(2), confidence: }
      end

      def host_budget_block(input)
        msg = Master::Ground::HostBudget.refuse_heavy_prompt?(input)
        return unless msg

        Master::Result.err(msg, category: :validation)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.host_budget_block")
        Master::Result.err("host budget unavailable: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def host_oom_message
        tip = Master::Ground::HostBudget.heavy_repo_message
        "failed to allocate memory - #{tip}"
      rescue StandardError
        "failed to allocate memory - use /fix lib or bin/master --fast"
      end

      def budget_block_if_exceeded
        max = @refs.session.budget_max.to_f
        return if max <= 0
        return if @refs.session.cost.to_f < max

        Master::Result.err(
          "budget exceeded: ¢#{( @refs.session.cost * 100).round(2)} / ¢#{(max * 100).round(2)} - use /cost or raise budget",
          category: :budget,
        )
      end

    end
  end
end
