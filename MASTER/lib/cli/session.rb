# frozen_string_literal: true

require_relative "session/container"
require_relative "session/thinking_indicator"
require_relative "activity"
require_relative "session/result_display"
require_relative "../ground/assistant_tasks"
require_relative "session/repl_flow"
require_relative "welcome"
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
        Master::Voice::Playback.state_listener = method(:announce_voice_status)
        @refs.agent.pin_boot_model! if @refs.agent.respond_to?(:pin_boot_model!)
        @refs.session.load! if @refs.session.exists?
        start_background_loop if background_scan_enabled?
        # Finish the compact boot surface before presenting the operator prompt.
        # Repository inventory and first-run hints remain available on demand.
        print_splash
        terminal_puts(@refs.renderer.session_line(@refs.session.messages.size)) if @refs.session.name
        paint_voice_indicators
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
        if turn_cancel_requested?
          cancelled = Master::Result.err("turn cancelled before start", category: :abort)
          publish_operation_log(operation: input, status: "cancelled", output: cancelled.message.to_s)
          return cancelled
        end
        blocked = check_budget_blocks(input)
        if blocked
          detail = blocked.respond_to?(:message) ? blocked.message.to_s : blocked.to_s
          publish_operation_log(operation: input, status: "blocked", output: detail)
          return blocked
        end

        @refs.ground_truth&.begin_turn! if @refs.respond_to?(:ground_truth)
        @user_active = true
        @last_input = input
        announce_voice_status
        Master::Trace::WriteTracker.current&.reset!
        paste, state, accumulated = init_turn_state(input)

        print_thinking_indicator unless paste
        operation_log_start = operation_log_snapshot
        result = dispatch_turn(input, accumulated:, state:)
        stop_thinking_indicator
        print_bridge_footer(result.value[:core], state:) if result.ok? && state[:streamed] && result.value[:core]
        display_result(
          result:, accumulated:,
          streamed: state[:streamed] && !state[:stream_suppressed],
          units_console: state[:units_console]
        )
        publish_operation_log(
          operation: input,
          status: result.ok? ? "success" : "failure",
          output: result.ok? ? success_text(result) : result.message.to_s,
          since: operation_log_start,
        )
        @last_repeatable_input = input if result.ok? && Master::Io::MediaIntent.repeatable?(input)

        result
      ensure
        @pipeline_thread = nil
        @turn_cancellation = nil
        stop_thinking_indicator
        close_unit_console
        @user_active = false
        announce_voice_status
      end

      private

      # Rendering the first cached WAV is CPU work. It must not sit between
      # the boot message and the operator's first prompt.
      def play_boot_sound
        return unless Master::Voice::BootSound.enabled?

        @boot_sound_thread = Thread.new do
          Thread.current.priority = -3
          Master::Voice::BootSound.play
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.boot_sound", event_bus: @refs.bus)
        end
        @boot_sound_thread.abort_on_exception = false
        @boot_sound_thread.report_on_exception = false
        @boot_sound_thread.name = "master-boot-sound" if @boot_sound_thread.respond_to?(:name=)
        @boot_sound_thread
      end

      def init_session_state!
        @running = false
        @last_ok = true
        @last_outcome = nil
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
        @voice_mic_active = false
        @voice_listen_active = false
      end

      def init_turn_state(input)
        paste = paste_like_input?(input)
        state = {
          streamed: false,
          thinking_shown: !paste,
          conversational: conversational_input?,
        }
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
          # A listener may receive events while normal mode deliberately hides
          # unit rows. Suppress the Fold transcript only when those rows render.
          next state[:streamed] = state[:units_console] = true if @unit_sub && verbose_output?

          accumulated << line << "\n"
          handle_stream_text(line + "\n", state) if $stdout.isatty
        end
      end

      # The reply as the model writes it: the first words reach the terminal seconds before the last.
      def build_on_chunk_handler(accumulated, state)
        lambda do |chunk|
          text = chunk.to_s
          next if text.empty?

          accumulated << text
          handle_stream_text(text, state) if $stdout.isatty
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
        if state[:conversational]
          return if state[:stream_suppressed]

          unless state[:chat_stream_started]
            state[:stream_probe] ||= +""
            state[:stream_probe] << text.to_s
            if ruby_say_wrapper_stream?(state[:stream_probe])
              state[:stream_suppressed] = true
              state[:stream_probe] = nil
              return
            end
            return if ruby_say_wrapper_prefix_pending?(state[:stream_probe])

            text = state[:stream_probe]
            state[:stream_probe] = nil
            state[:chat_stream_started] = true
          end
          text = format_conversation_stream(text, state:)
        elsif state[:stream_suppressed]
          return
        end

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
        terminal_print(wrap_stream(text, state), guard: false, preserve_blank_lines: true)
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

      private

      def setup_signals
        trap("USR1") { on_usr1 }
        trap("INT")  { on_int }
      end

      # Master::LOADER is the loader that owns lib/; reloading is on only under
      # MASTER_DEV=1, and Zeitwerk raises on reload otherwise.
      def on_usr1
        unless Master::LOADER.reloading_enabled?
          Master::Trace::Dmesg.status("reload0", "skipped, reloading is off without MASTER_DEV=1")
          return
        end

        Master::LOADER.reload
        Master::Trace::Dmesg.status("reload0", "complete")
      rescue StandardError => e
        Master::Trace::Dmesg.status("reload0", "failed, #{e.class}: #{e.message}")
      end

      # ^C cancels a running turn; at the prompt it ends the session. A trap
      # interrupts the main thread wherever it stands, where taking a mutex
      # raises ThreadError, so the cancel runs on a thread of its own and the
      # prompt raises Interrupt for repl_loop to close in ordinary context.
      def on_int
        if @voice_listen_active
          @voice_listen_stop = true
          turn = @pipeline_thread
          if turn&.alive?
            return Thread.new { request_or_interrupt_turn(turn, @turn_children, reason: "ctrl_c") }
          end
          raise Interrupt
        end

        turn = @pipeline_thread
        if turn&.alive?
          # In the interactive queue, Ctrl+C has the same safe semantics as
          # /stop: pause queued turns too. Do mutex work outside the signal trap.
          return Thread.new { stop_interactive_queue(reason: "ctrl_c") } if @turn_worker&.alive?
          return Thread.new do
            @turn_queue_mutex.synchronize { @turn_cancel_requested = true }
            request_or_interrupt_turn(turn, @turn_children, reason: "ctrl_c")
          end
        end

        raise Interrupt
      end

      # Fold-owned work observes cancellation between model, policy and
      # effect boundaries. Do not kill its thread mid-transaction; non-Fold
      # commands retain the established immediate interruption path.
      def request_or_interrupt_turn(turn, children, reason:)
        token = @turn_cancellation
        cancellation_reason = case reason.to_s
                              when "ctrl_c" then "Ctrl-C requested cancellation"
                              when "stop" then "/stop requested cancellation"
                              else "operator requested cancellation"
                              end
        token&.cancel!(reason: cancellation_reason)
        if token&.active?
          answer_pending_terminal_ask("/deny") if terminal_ask_pending?
          @refs.bus&.publish("user:interrupt", reason:, source: "cli", children:)
        else
          cancel_turn(turn, children, reason:)
        end
      end

      # The thread first, so the turn takes no next step, then its children,
      # which the thread is otherwise left waiting on. Preserve the initiating
      # control in the receipt; /stop must not be recorded as Ctrl-C.
      def cancel_turn(turn, children, reason: "ctrl_c")
        turn.kill
        @refs.bus&.publish("user:interrupt", reason:, source: "cli", children:)
      end

      private

      def toggle_focus
        @focus_mode = !@focus_mode
        Master::Trace::Dmesg.status("focus0", @focus_mode ? "on" : "off")
      end

      private

      def start_background_loop
        # Built on the main thread, before either scanner thread exists, so both
        # find the same check rather than racing to create one.
        @scan_check = Mutex.new
        @bg_thread = Thread.new do
          loop do
            break if background_stop_requested?

            background_cycle unless @user_active
          end
        rescue StandardError => e
          @refs.bus&.publish("cli:bg_error", error: e.message)
        end
      end

      # Public: bin/master stops the loop on its way out.
      public def stop_background_loop
        @boot_scan_thread&.kill
        @boot_scan_thread = nil
        return unless @bg_thread

        @bg_control << :stop
        @bg_thread.join(2)
        @bg_thread = nil
      end

      # A blocking pop with a timeout. A non-blocking pop raises ThreadError on
      # every empty tick, and the swallow ledger would record one a second.
      def background_stop_requested?
        @bg_control.pop(timeout: IDLE_SLEEP_DEFAULT) == :stop
      end

      # The deep self-scan over lib/ runs 181 rules and takes north of a minute.
      # Inline it held the prompt hostage for the whole boot, so the operator sat
      # at "scan…" with no way to type. It reports when it lands instead.
      def start_boot_scan
        @boot_scan_thread = Thread.new do
          # The scan is pure Ruby and holds the GVL for whole time slices, so a plain
          # "hello" waited behind it for 58 seconds. MRI scales a thread's slice by its
          # priority; the lowest keeps the prompt's turns short while the scan lands.
          Thread.current.priority = -3
          @scan_check.synchronize { Master::Trace::Dmesg.under("scan0") { boot_scan } }
        end
      end

      # Rules that call the model (AdversarialRule, SemanticLaw, CommentDriftRule
      # — anything mixing in Rules::NeedsModel) share the one local ollama process
      # with the interactive turn. Running them here queued a plain "hey" behind
      # 8 sequential model calls the operator never asked for — /fix
      # still run the full rule set, deliberately, when a person asks for it.
      def mechanical_scanner_rules
        @refs.scanner.laws.reject { |law| law.respond_to?(:agent?) }
      end

      def boot_scan
        result = Master::Review::Scan::SelfScan.new(scanner: @refs.scanner, root: @refs.root, event_bus: @refs.bus,
          laws: mechanical_scanner_rules).call(autofix: false)
        return unless result.ok?

        summary = result.value!
        set_violations(summary.violation_count)
        Master::Trace::Dmesg.status("scan0", boot_scan_line(summary).delete_prefix("scan0: "))
      rescue StandardError => e
        @refs.bus&.publish("cli:warn", error: e.message)
      end

      # The count and the command that acts on it, in one line. A count alone
      # invites "fix them", and a sentence reaches the read-only preview; /fix
      # is the stage that writes.
      def boot_scan_line(summary)
        count = summary.violation_count
        return "scan0: lib/ clean, #{summary.rule_count} rules" if count.zero?

        "scan0: lib/ #{count} #{count == 1 ? 'violation' : 'violations'}, #{summary.rule_count} rules; /fix lib repairs them"
      end

      def run_self_scan
        result = Master::Review::Scan::SelfScan.new(scanner: @refs.scanner, root: @refs.root, event_bus: @refs.bus).call(stream: true, autofix: true)
        if result.ok?
          Master::Trace::Dmesg.status("scan0", result.value!.line.delete_prefix("scan0: "))
        else
          Master::Trace::Dmesg.status("err0", result.message)
        end
      end

      def scan_files(paths)
        Result.ok(paths.map { |p| [p, @refs.scanner.scan(p, depth: :deep)] })
      end

      def count_violations(pairs)
        pairs.sum do |_file, file_result|
          file_result.ok? ? file_result.value!.size : 0
        end
      end

      # Skips rather than queues: this fires every idle_sleep_seconds, and a tick
      # that waited its turn would only start a redundant rescan of a tree the
      # in-flight scan is already covering.
      def background_cycle
        return unless @scan_check.try_lock

        begin
          Master::Trace::Dmesg.under("scan0") { background_cycle! }
        ensure
          @scan_check.unlock
        end
      end

      def background_cycle!
        lib_dir = File.join(@refs.root, "lib")
        result = @refs.scanner.scan_dir(lib_dir, depth: :deep, laws: mechanical_scanner_rules)
        return unless result.ok?
        n = count_violations(result.value!)
        prev = violations_count
        return if n == prev
        delta = n - prev
        set_violations(n)
        sign = delta.positive? ? "+#{delta}" : delta.to_s
        msg = n.positive? ? "scan0: lib/ #{n} violations, #{sign}" : "scan0: lib/ clean, #{sign}"
        Master::Trace::Dmesg.status("scan0", msg.delete_prefix("scan0: "))
        @refs.bus&.publish("cli:violation_delta", count: n, delta:, previous: prev)
      rescue StandardError => e
        @refs.bus&.publish("cli:bg_error", error: e.message)
      end

      def refresh_skills!
        @refs.skills&.discover!
      end

      # Rings a task whose due time has passed, once: a remind0 line above the
      # prompt, the same words spoken, and a reminder:due event for the face. Only
      # an open interactive session rings; AssistantTasks::DELIVERY says so when a
      # due time is accepted.
      REMINDER_POLL_S = 30

      private

      def start_reminder_watch
        return unless $stdin.tty? && $stdout.tty?
        return if Fiber[:master_visitor] == true

        @reminder_thread = Thread.new do
          loop do
            ring_due_reminders
            sleep REMINDER_POLL_S
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.reminders", event_bus: @refs.bus)
        end
      end

      def stop_reminder_watch
        @reminder_thread&.kill
        @reminder_thread = nil
      end

      def ring_due_reminders(tasks: Master::Ground::AssistantTasks.new(root: @refs.root, bus: @refs.bus))
        tasks.due_reminders.each do |task|
          next unless claim_reminder(tasks, task.fetch("id"))

          terminal_puts("remind0: #{task.fetch('title')}")
          redraw_active_input
          @refs.bus&.publish("reminder:due", task_id: task.fetch("id"))
          Master::Voice::Playback.speak("Reminder: #{task.fetch('title')}")
        end
      end

      # Another session that rang it first wins; this one stays quiet.
      def claim_reminder(tasks, id)
        tasks.call(action: "reminded", id:)
        true
      rescue Master::Ground::AssistantTasks::Error
        false
      end

      private

      # The live-state welcome is enough at startup. A second model request can
      # occupy the same provider lane as the operator's first turn.
      # Keep the personal greeting available as an explicit opt-in.
      # MASTER_GREETING=1 enables it.
      def greet_from_model
        return unless ENV["MASTER_GREETING"] == "1" && $stdout.tty?

        Thread.new { deliver_greeting }
      end

      # A greeting that arrives after the operator has started talking is stale, and it printed onto the end of
      # the first reply ("...or mainly you?Late for hard conversations, Johann."), so it stands down.
      def deliver_greeting
        text = @refs.agent.ask_once(greeting_prompt, law: false).to_s.strip
        return if text.empty? || @user_active || !@last_input.to_s.empty? || @pipeline_thread

        terminal_puts(@refs.renderer.render(text.lines.first.to_s.strip, mode: :dim))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.greeting", event_bus: @refs.bus)
      end

      GREETING_LANGUAGES = { nb: "Norwegian Bokmål", ms: "Malay", en: "English" }.freeze

      def greeting_prompt
        context = Master::CLI::Welcome.context(Master::ROOT)
        # Read only the language signal locally. The previous words and topic
        # never enter the model greeting prompt or public boot scrollback.
        session = Master::CLI::Welcome.read_session(Master::ROOT)
        last_user = Array(session["messages"]).reverse.find { |message| message["role"] == "user" }
        language = GREETING_LANGUAGES.fetch(Master::Voice::Language.detect(last_user&.fetch("content", nil)), "English")

        <<~PROMPT
          You are MASTER, greeting the operator as a terminal session opens. One natural line of at most
          twelve words, in #{language}. Be warm without being familiar or theatrical. Do not quote, infer,
          or refer to earlier conversation, personal history, mood, or private topics. Do not ask a question.

          Now: #{context[:time]}. #{context[:line]}.
        PROMPT
      end

      private

      # The summary is the reply, so it sits at full weight under the units.
      # The final streamed reply is spoken by result_display; speaking this
      # summary here too queued the same turn a second time.
      # The fold's own line comes from the units console when one ran, and
      # from here when none did.
      def print_bridge_footer(fold, state:)
        summary = fold[:summary].to_s.strip
        puts
        unless summary.empty?
          puts @refs.renderer.measure(summary, width: reply_measure)
        end
        Master::Trace::Dmesg.status("fold0", "#{fold[:reason]}, #{fold[:turns]} turns") unless @unit_sub
      end
    end
  end
end
