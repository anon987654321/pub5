# frozen_string_literal: true

require_relative "repl_io"
require_relative "../face/transcriber"
require_relative "../face/ear"
require_relative "../stages/route"
require_relative "../turn_router"

module Master
  module CLI
    class Session
      CONTEXT_STEP = 10_000
      CLOSE_WINDOW_S = 3
      INTERACTIVE_QUEUE_LIMIT = 32
      BANG = /\A!(?<command>\S.*)\z/m

      # Slash verbs that answer from local state and may run while a model turn
      # streams (Johann's log 2026-11-08: /voice, /tts and /help typed during an
      # 89-second turn queued four to six deep, so the operator toggled session
      # sound for a conversation that had already moved on). Everything else
      # keeps its place in the queue: a writing verb must not interleave with
      # the turn that is running.
      TURN_SAFE_COMMANDS = %w[capabilities doctor help laws model status voice].freeze

      # Slash verbs the REPL itself answers before any registry lookup: the
      # mic, the two exits, and the queue and ask controls. They are not
      # registry names, so the unknown-command refusal must not reach them.
      REPL_SLASH = %w[approve deny exit listen quit resume stop].freeze

      # The verbs a busy turn still answers, spelled out because the door
      # works before the registry has loaded: /help, the voice controls and
      # the model's read-only questions run now, anything that can start
      # another long job stays FIFO-queued behind the turn.
      BUSY_TURN_CONTROLS = %w[capabilities doctor laws model status voice].freeze

      private

      module ReplFlow
        private


        def set_visitor_mode_if_unauthenticated
          # Visitor is a web-request flag, set per request on ai.brgen.no.
          # The local CLI is the operator surface: treating a missing web_token
          # as a visitor handed `bin/master "read CLAUDE.md"` AskLlm and
          # WebSearch, no ReadFile, and a 45-cent reply asking for the text.
        end

        # ^D reads nil and closes the session. ^C at the prompt clears the line, as
        # zsh does, and a second ^C inside CLOSE_WINDOW_S closes it: on a phone
        # keyboard one stray press cost the session. A second ^C while it closes
        # exits at once, so a save stuck on a full disk cannot hold the terminal.
        def repl_loop
          while @running
            line = read_prompt_line
            break if line.nil?

            handle_repl_line(line) unless line == :interrupted
          end
        rescue Interrupt
          terminal_puts
        ensure
          trap("INT") { exit!(130) }
          close_session
        end

        def read_prompt_line
          # Prompt-state output is emitted while computing the prompt. Reline does
          # not own the editable row until readline starts, so do not clear or
          # redisplay a draft that does not exist yet.
          @active_prompt = prompt_for_mode
          @reading_input = true
          reserve_activity_row
          line = safe_read_line(@active_prompt)
          terminal_puts if line.nil?
          line
        rescue Interrupt
          terminal_puts
          return if close_requested?

          Master::Trace::Dmesg.status("cli0", "^C again to exit")
          :interrupted
        ensure
          # The read ends before the bookkeeping write, so the write's guard
          # hooks see a closed read instead of pushing rows past the submitted
          # line's own newline.
          @reading_input = false
          Master::Trace::Dmesg.terminal_write(guard: false) do |_target|
            @activity_row_reserved = false
            @active_prompt = nil
          end
        end

        # Start the quiet interval for a queued turn, but do not insert an
        # empty terminal row. ThinkingIndicator reserves and paints one only
        # after the event stream has settled.
        def reserve_activity_row
          return unless $stdin.tty? && $stdout.tty?

          busy = @turn_queue_mutex.synchronize do
            @turn_worker&.alive? && !@turn_queue_paused && !@closed
          end
          @last_foreign_write_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) if busy
        rescue StandardError => e
          @activity_row_reserved = false
          Master::Ground::Swallow.log(e, context: "cli.activity_row.reserve", event_bus: @refs.bus)
        end

        def close_requested?
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          recent = @interrupted_at && now - @interrupted_at <= CLOSE_WINDOW_S
          @interrupted_at = now
          recent
        end

        def close_session
          return if @closed

          @closed = true
          shutdown_interactive_queue! if $stdin.tty? && $stdout.tty?
          stop_background_loop
          stop_reminder_watch
          save_cli_history
          save_session_on_exit
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.close_session", event_bus: @refs.bus)
        end

        def prompt_for_mode
          refresh_skills!
          @focus_mode ? focus_prompt : normal_prompt
        end

        # Reline owns the working prompt and line editor; the face is an
        # append-only visual layer above it, never a terminal-input handoff.
        def normal_prompt
          prompt_with(focused: false)
        end

        # Focus mode reduces context noise, never hides the working location or
        # the destination that receives the next line of text.
        def focus_prompt
          prompt_with(focused: true)
        end

        def prompt_with(focused:)
          state, prompt = @refs.renderer.prompt_line(
            @refs.agent.model, @refs.session.phase,
            last_ok: @last_ok, violations: violations_count,
            tokens: @refs.session.token_est, cost: @refs.session.cost,
            focused:
          )
          announce_state(state)
          prompt
        end

        # The state line prints only when its meaning moves, so the prompt keeps
        # one shape. Token drift is not news: the context count moves with every
        # turn, and a line that moved for that alone repainted the same fact.
        # Lane, model, violations and error are the meaning; the count rides
        # along whenever the line prints at all.
        #
        # The renderer emits the count as one whole comma field — token_label
        # prints "12.5k" or "1.0M" above the thresholds, a bare count below
        # ("260/128.0k", Johann's log 2026-11-08) — so a strip regex demanding
        # a suffix on the first number never matched and the line repainted
        # between prompts on every turn. The meaning drops the whole field
        # instead of cutting the tail off the string.
        STATE_TOKEN_COUNT = /\A\d+(?:\.\d+)?[kM]?\/\d+(?:\.\d+)?[kM]?\z/.freeze

        def announce_state(state)
          return if state.nil? || same_state_meaning?(state, @announced_state)

          @announced_state = state
          terminal_puts(state)
        end

        def same_state_meaning?(state, previous)
          return false if previous.nil?

          state_meaning(state) == state_meaning(previous)
        end

        # What a person decides on: model, violations, error. The git segment
        # drifts with every save (ahead/dirty), the phase word with every
        # stage, the token count with every turn — the log showed "main dirty
        # llm discover, grok-cli:auto, 270/128.0k" repainting between prompts
        # with nothing new to say (Johann 2026-11-08). The prompt below the
        # state line already carries git and phase live, so the meaning
        # compares without them.
        def state_meaning(state)
          fields = state.to_s.split(", ", -1)
          operator = fields.shift.to_s.split
          meaning = fields.reject { |field| field.match?(STATE_TOKEN_COUNT) }
          meaning.unshift("error") if operator.include?("error")
          meaning.join(", ")
        end

        # An empty line does nothing, as in a shell: Enter never runs an action
        # the operator has not read.
        def handle_repl_line(line)
          stripped = line.strip
          return if stripped.empty?

          if stripped.casecmp("/stop").zero?
            return stop_interactive_queue if queue_control_mode? || @turn_worker&.alive?
            terminal_puts("queue0: no active turn")
            return
          end
          if stripped.casecmp("/resume").zero?
            return resume_interactive_queue if @turn_queue_paused
            terminal_puts("queue0: queue is not paused")
            return
          end
          return exit_cli if queue_control_mode? && %w[/exit /quit].include?(stripped.downcase)
          if Thread.current != @turn_worker && terminal_ask_pending?
            return if answer_pending_terminal_ask(stripped)
            accepted = enqueue_interactive_line(line)
            terminal_puts("ask0: approval pending; enter /approve or /deny, your message is queued") if accepted
            return
          end
          if @turn_worker&.alive? && Thread.current != @turn_worker
            # Keep the operator surface responsive while a model turn is busy.
            # Deterministic controls do not become conversational queue entries:
            # /help, voice controls and governed shell commands must run now.
            handled = dispatch_busy_operator_control(stripped)
            return handled unless handled == :unhandled
            return refuse_unknown_slash_command(stripped) if unknown_slash_command?(stripped)

            enqueue_interactive_line(line)
            return
          end

          case Master::CLI::OperatorGrammar.parse(stripped)&.kind
          when :repeat then return repeat_last
          when :toggle_focus then return toggle_focus
          when :direct_shell then return run_direct_shell(stripped)
          end

          handled = dispatch_core_slash_command(stripped)
          return handled unless handled == :unhandled

          bang = stripped.match(BANG)
          return run_bang(bang[:command]) if bang
          return run_input(read_multiline) if stripped == "<<"
          return refuse_unknown_slash_command(stripped) if unknown_slash_command?(stripped)

          run_agent_turn(line)
        end

        # A busy model turn must not capture local controls as future prompts.
        # Keep this allowlist deliberately small: commands that can start another
        # long-running job remain FIFO-queued behind the active turn. A /cd must
        # not race the turn reading the old directory, so it queues too. A typo
        # is refused, not queued: an unknown word is not prose waiting its turn
        # (Johann's log 2026-11-08).
        def dispatch_busy_operator_control(stripped)
          case Master::CLI::OperatorGrammar.parse(stripped)&.kind
          when :repeat then return repeat_last
          when :toggle_focus then return toggle_focus
          when :direct_shell
            return :unhandled if directory_change_command?(stripped)
            return run_direct_shell(stripped)
          end

          if (help_match = stripped.match(%r{\A/(?:help|\?)(?:\s+(.+))?\z}))
            return run_help(help_match[1])
          end

          match = stripped.match(%r{\A/(?<name>[a-z][a-z0-9_-]*)(?:\s+(?<args>.*))?\z}i)
          return :unhandled unless match

          original = match[:name].downcase
          name = Stages::Route::SPELLINGS.fetch(original, original)
          args = match[:args].to_s
          return :unhandled unless BUSY_TURN_CONTROLS.include?(name)
          # Mid-turn, the model verbs answer read-only questions only: a model
          # switch would move the ground under the turn still running.
          return :unhandled if name == "model" && !args.match?(/\A(?:|list|status|current)\z/i)
          return :unhandled if name == "voice" && !args.match?(/\A(?:|status|on|off|natural|normal|classic|fast|expressive|transcendent|dilla)\z/i)

          dispatch_registered_slash_command(original == "tts" ? "/voice#{args.empty? ? "" : " #{args}"}" : stripped)
        end

        # A line shaped like "/word" is a command request, not prose. The
        # pipeline door already refuses an unknown one (Stages::Route); the REPL
        # door used to hand it to the model instead, which cost a 60-90 second
        # spin answered by the model's guess about a surface it does not own
        # ("I can't run that command or access a model selector here", Johann's
        # log 2026-11-08). The pipeline's spellings stay exempt: /sweep, /prove
        # and /fold are not registry names - they are /fix and the fold wearing
        # another word.
        def unknown_slash_command?(stripped)
          match = stripped.match(%r{\A/(?<name>[a-z][a-z0-9_-]*)}i)
          return false unless match

          name = match[:name].downcase
          return false if REPL_SLASH.include?(name)
          return false if TurnRouter::PIPELINE_SLASH.include?(name)
          return false if TurnRouter::FOLD_SLASH.include?(name)

          registered_command_name(name).nil?
        end

        def refuse_unknown_slash_command(stripped)
          name = stripped.sub(%r{\A/}, "").split(/\s+/, 2).first.to_s.downcase
          suggestion = Stages::Route.suggestion_for(name, @container.fetch(:commands, {}).keys)
          message = "unknown command: /#{name}"
          message += suggestion ? " - did you mean /#{suggestion}?" : " - /help lists the surface"
          print_terminal_output(message, mode: :error)
          nil
        end

        # One name table for both doors: the pipeline's spellings (/tts is
        # /voice) resolve before the registry lookup, so the REPL and the
        # pipeline answer a spelling with the same verb.
        def registered_command_name(name)
          name = Stages::Route::SPELLINGS.fetch(name, name)
          commands = @container.fetch(:commands, {})
          commands.key?(name) ? name : nil
        end

        def turn_safe_slash_command?(stripped)
          match = stripped.match(%r{\A/(?<name>[a-z][a-z0-9_-]*)}i)
          return false unless match

          name = registered_command_name(match[:name].downcase)
          !name.nil? && TURN_SAFE_COMMANDS.include?(name)
        end

        def dispatch_core_slash_command(stripped)
          case stripped
          when %r{\A/(?:help|\?)(?:\s+(.+))?\z} then run_help(Regexp.last_match(1))
          when "/exit", "/quit" then exit_cli
          when "/undo", "/clear" then dispatch_registered_slash_command(stripped)
          when "/listen" then run_listen
          else dispatch_registered_slash_command(stripped)
          end
        end

        # Slash commands are already a closed, tested registry. Sending a known
        # slash command through the LLM makes deterministic commands probabilistic:
        # /play can become a model turn, return nil after cancellation, or revive
        # stale natural-language media behavior. Direct registered dispatch keeps
        # the CLI faithful to its command surface.
        def dispatch_registered_slash_command(stripped)
          stripped = Stages::Route.rewrite_spelling(stripped)
          match = stripped.match(%r{\A/(?<name>[a-z][a-z0-9_-]*)(?:\s+(?<args>.*))?\z}i)
          return :unhandled unless match

          name = registered_command_name(match[:name].downcase)
          command = name && @container.fetch(:commands, {})[name]
          return :unhandled unless command

          @refs.ground_truth&.begin_turn! if @refs&.respond_to?(:ground_truth)
          result = command.call(args: match[:args].to_s)
          # Pipe mode (`bin/master /fix RAILS` with no TTY) reaches commands here, and bin/master
          # exits with @exit_code: a failed command must not exit 0.
          text = if result.is_a?(Master::Result)
                   @last_ok = result.ok?
                   @exit_code = result.ok? ? 0 : exit_code_for(result)
                   result.ok? ? result.value!.to_s : result.message.to_s
                 else
                   @last_ok = true
                   @exit_code = 0
                   result.to_s
                 end
          # Read-only model selector output is runtime evidence for the next turn.
          # Other commands may expose private state, so they are not copied wholesale.
          record_model_selector_output(args: match[:args].to_s, text:, success: @last_ok) if name == "model"
          # The commands' replies print here; the face transcript is gone with
          # the terminal face.
          print_terminal_output(text, mode: @last_ok ? :dim : :error) unless text.empty?
          result
        rescue StandardError => e
          @last_ok = false
          @exit_code = 2
          text = "cmd0: /#{name} failed - #{e.class}: #{e.message}"
          print_terminal_output(text, mode: :error)
          nil
        end

        # One deliberate microphone capture. Ear enforces both local grants and
        # leaves Android OS permission to the Termux:API app; no background mic.
        def run_listen
          ear = Face::Ear.new(root: @refs.respond_to?(:root) ? @refs.root : Master::REPO_ROOT)
          if (missing = ear.missing)
            terminal_puts(missing)
            return
          end

          terminal_puts("mic0: listening")
          transcript = ear.listen(stop: -> { false }, on_partial: nil).to_s.strip
          return terminal_puts("mic0: heard nothing") if transcript.empty?

          run_agent_turn(transcript)
        rescue StandardError => e
          terminal_puts("mic0: capture failed - #{e.class}: #{e.message}")
          nil
        end

        # !command runs one zsh line through the Io::Shell the model's zsh tool
        # uses — its blocklist, sandbox, interactive refusal and governor — and
        # costs no model call. The output joins the transcript so the next prompt
        # can refer to it. Fast mode builds no governor, so it refuses.
        def run_bang(command)
          shell = bang_shell
          return Master::Trace::Dmesg.status("shell0", "governor unavailable") unless shell

          result = shell.call(command:)
          text = result.ok? ? result.value!.to_s : result.message.to_s
          record_execution_output(command:, text:, status: result.ok? ? "success" : "failure")

          terminal_puts(@refs.renderer.render(text, mode: result.ok? ? :dim : :error))
        end

        # Terminal output is attached to the session as execution evidence. The model
        # sees only output the operator actually requested and that the runtime
        # explicitly captured; it does not get a fictional live view of stdout.
        EXECUTION_CONTEXT_MAX_BYTES = 12_000
        EXECUTION_COMMAND_MAX_BYTES = 1_000
        private_constant :EXECUTION_CONTEXT_MAX_BYTES, :EXECUTION_COMMAND_MAX_BYTES
        EXECUTION_ANSI = /\e(?:\[[0-?]*[ -\/]*[@-~]|\][^\a]*(?:\a|\e\\))/

        def record_execution_output(command:, text:, status: "unknown")
          output = bounded_execution_text(text, EXECUTION_CONTEXT_MAX_BYTES)
          return if output.empty?
          return unless @refs.respond_to?(:session) && @refs.session.respond_to?(:add_message)

          command_text = bounded_execution_text(command, EXECUTION_COMMAND_MAX_BYTES)
          outcome = %w[success failure changed unknown].include?(status.to_s) ? status.to_s : "unknown"
          @refs.session.add_message(
            role: :user,
            content: "[untrusted execution evidence; status=#{outcome}; output may be truncated]\n$ #{command_text}\n#{output}",
            layer: :execution,
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.execution_output", event_bus: @refs.bus)
        end

        def record_model_selector_output(args:, text:, success: true)
          return unless %w[list status current].include?(args.to_s.strip.downcase) || args.to_s.strip.empty?

          record_execution_output(command: "/model #{args}".strip, text:, status: success ? "success" : "failure")
        end

        def bounded_execution_text(value, max_bytes)
          text = Master::Ground::Redactor.text(value.to_s.scrub.gsub(EXECUTION_ANSI, ""))
          return text if text.bytesize <= max_bytes

          "#{text.byteslice(0, max_bytes).to_s.scrub}\n[execution output truncated]"
        end

        def bang_shell
          governor = @container[:governor]
          return unless governor

          @bang_shell ||= Master::Io::Shell.new(root: Dir.pwd, governor:, event_bus: @refs.bus)
        end

        def directory_change_command?(command)
          Shellwords.split(command.to_s).first == "cd"
        rescue ArgumentError
          false
        end

        # A directory change belongs to the REPL process, not a short-lived
        # child shell. It is deliberately queued during a model turn because
        # Dir.chdir is process-wide and would race tools using relative paths.
        # Keep navigation inside the checkout; governed commands inherit the
        # new working directory on their next invocation.
        def change_directory(command)
          args = Shellwords.split(command.to_s)
          return :unhandled unless args.first == "cd"
          return directory_change_failure("usage: cd [directory]") if args.length > 2

          target = args.fetch(1, "")
          target = ENV["OLDPWD"].to_s if target == "-"
          target = Dir.home if target.empty?
          target = File.expand_path(target, Dir.pwd)
          destination = File.realpath(target)
          workspace = File.realpath(Master.repo_root)
          unless destination == workspace || destination.start_with?("#{workspace}#{File::SEPARATOR}")
            return directory_change_failure("outside checkout: #{destination}")
          end

          previous = Dir.pwd
          Dir.chdir(destination)
          ENV["OLDPWD"] = previous
          @bang_shell = nil
          record_execution_output(command:, text: Dir.pwd, status: "changed")
          @last_ok = true
          @exit_code = 0
          terminal_puts(@refs.renderer.render(Dir.pwd, mode: :dim))
          :changed
        rescue SystemCallError, ArgumentError => e
          directory_change_failure("#{e.class}: #{e.message}")
        end

        def directory_change_failure(message)
          @last_ok = false
          @exit_code = 1
          terminal_puts(@refs.renderer.render("cd0: #{message}", mode: :error))
          :failed
        end

        def run_direct_shell(command)
          changed = change_directory(command)
          return changed unless changed == :unhandled

          shell = bang_shell
          return Master::Trace::Dmesg.status("shell0", "unavailable") unless shell

          result = shell.call(command:)
          text = result.ok? ? result.value!.to_s : result.message.to_s
          record_execution_output(command:, text:, status: result.ok? ? "success" : "failure")
          @last_ok = result.ok?
          @exit_code = result.ok? ? 0 : 2

          # Like run_bang: the write shares Dmesg's mutex and rebuilds Reline's
          # draft, instead of appending at the cursor after the prompt glyphs.
          terminal_puts(@refs.renderer.render(text, mode: result.ok? ? :dim : :error))
        end

        def repeat_last
          input = @last_repeatable_input.to_s
          return Master::Trace::Dmesg.status("cli0", "nothing to repeat") if input.empty?

          run_input(input)
        end

        def run_agent_turn(line)
          if (refusal = host_refusal_for(line))
            Master::Trace::Dmesg.status("host0", refusal)
            return
          end

          if $stdin.tty? && $stdout.tty? && Thread.current != @turn_worker
            enqueue_interactive_line(line)
          else
            run_input(line.strip)
          end
        end

        def queue_control_mode?
          @turn_queue_paused || (@turn_worker&.alive? && Thread.current != @turn_worker)
        end

        def shutdown_interactive_queue!
          @turn_queue_mutex&.synchronize do
            @turn_queue&.clear
            @turn_queue_paused = true
            @turn_cancel_requested = true
          end
          turn = @pipeline_thread
          if turn&.alive? && Thread.current != @turn_worker
            canceler = Thread.new { request_or_interrupt_turn(turn, @turn_children, reason: "stop") }
            canceler.join(1)
            turn.join(1)
          end
          worker = @turn_worker
          worker.join(1) if worker&.alive? && Thread.current != worker
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.queue.shutdown", event_bus: @refs.bus)
        end

        def interactive_queue_count
          @turn_queue_mutex.synchronize { @turn_queue.length }
        rescue StandardError
          0
        end

        def enqueue_interactive_line(line)
          count = nil
          busy = false
          paused = false
          full = false
          @turn_queue_mutex.synchronize do
            if @turn_queue.length >= INTERACTIVE_QUEUE_LIMIT
              full = true
            else
              busy = !!@turn_worker&.alive?
              @turn_queue << line.to_s
              paused = @turn_queue_paused
              start_interactive_queue_worker_locked unless busy || paused || @closed
              count = @turn_queue.length
            end
          end
          if full
            terminal_puts("queue0: full, #{INTERACTIVE_QUEUE_LIMIT} pending; message not queued")
            false
          else
            terminal_puts("queue0: #{count} queued, paused") if paused && count&.positive?
            if busy && count&.positive? && !busy_turn_spinner_shows_queue?
              # The busy-turn spinner suffix already carries the count while it
              # paints its own row; appending a queue0 line here churned the
              # display (Johann 2026-11-07). Non-tty pipes keep the receipt.
              terminal_puts("queue0: #{count} queued")
            end
            true
          end
        end

        # True when the reserved activity row is being painted, so the count is
        # visible in the spinner suffix and its own receipt line would duplicate
        # nothing that is already on the screen.
        def busy_turn_spinner_shows_queue?
          $stdout.tty? && @activity_row_reserved && activity_row_safe_to_draw?
        rescue StandardError
          false
        end

        # Called with @turn_queue_mutex held. A startup latch replaces a busy
        # Thread.pass loop and makes worker ownership deterministic.
        def start_interactive_queue_worker_locked
          return if @closed || @turn_queue_paused || @turn_worker&.alive?

          ready = Queue.new
          worker = Thread.new do
            ready.pop
            drain_interactive_queue
          end
          worker.report_on_exception = false
          @turn_worker = worker
          ready << true
        end

        def drain_interactive_queue
          worker = Thread.current
          Thread.current.report_on_exception = false
          Fiber[:master_cli_container] = @container

          loop do
            line = take_next_interactive_line(worker)
            break if line.nil?
            next unless begin_interactive_line(line)

            # One receipt names the turn now running: with several lines queued,
            # the operator otherwise sees only a spinner and cannot tell which
            # message started. The brief cuts on a word boundary — a mid-word
            # cap turned "vm23" into "vm2" and read as a different host.
            terminal_puts("queue0: run: #{queue_question_brief(line)}") if $stdin.tty? && $stdout.tty?
            begin
              handle_repl_line(line)
            ensure
              finish_interactive_line(line)
            end
          end
        rescue StandardError => e
          # The message alone named nothing a person could act on: "undefined
          # method 'value' for true" (Johann's log 2026-11-08) sent the reader
          # hunting a call site with no address. The first frame is the address.
          where = e.backtrace&.first.to_s.sub(%r{\A.*/lib/}, "")
          terminal_puts("queue0: worker failed - #{e.class}: #{e.message} at #{where}", io: $stderr)
        ensure
          restart = false
          @turn_queue_mutex.synchronize do
            if @turn_worker.equal?(worker)
              @turn_worker = nil
              @turn_current_line = nil
              @turn_current_started = false
              restart = !@closed && !@turn_queue_paused && !@turn_queue.empty?
            end
          end
          if restart
            @turn_queue_mutex.synchronize { start_interactive_queue_worker_locked }
          end
        end

        def take_next_interactive_line(worker)
          @turn_queue_mutex.synchronize do
            if @closed || @turn_queue_paused || @turn_queue.empty?
              @turn_worker = nil if @turn_worker.equal?(worker)
              nil
            else
              @turn_current_line = @turn_queue.shift
              @turn_current_started = false
              @turn_current_line
            end
          end
        end

        # Stop can land between dequeue and execution. A line that has not crossed
        # this boundary is returned to the head of the FIFO instead of being lost.
        def begin_interactive_line(line)
          @turn_queue_mutex.synchronize do
            if @closed || @turn_queue_paused
              @turn_queue.unshift(line) if @turn_current_line.equal?(line) && !@turn_current_started && !@closed
              @turn_current_line = nil if @turn_current_line.equal?(line)
              @turn_current_started = false
              false
            else
              @turn_current_started = true if @turn_current_line.equal?(line)
              true
            end
          end
        end

        def finish_interactive_line(line)
          @turn_queue_mutex.synchronize do
            if @turn_current_line.equal?(line)
              @turn_current_line = nil
              @turn_current_started = false
            end
          end
        end

        def stop_interactive_queue(reason: "stop")
          active_operation = false
          @turn_queue_mutex.synchronize do
            @turn_queue_paused = true
            @turn_cancel_requested = true
            active_operation = !!(@turn_worker&.alive? && @turn_current_started)
          end
          turn = @pipeline_thread
          active_turn = turn&.alive?
          if active_turn
            # Use the same cancellation policy as Ctrl-C: Fold-owned work stops
            # at a safe boundary; only non-Fold work takes the immediate kill path.
            canceler = Thread.new { request_or_interrupt_turn(turn, @turn_children, reason:) }
            canceler.join(2)
            turn.join(1) unless Thread.current == turn
          end
          count = interactive_queue_count
          status = if active_turn
                     reason.to_s == "ctrl_c" ? "Ctrl-C cancellation requested" : "/stop cancellation requested"
                   elsif active_operation
                     "queue paused; current operation continues"
                   else
                     "queue paused; pending turn will not start"
                   end
          terminal_puts("queue0: #{status}; #{count} queued, /resume to continue")
          nil
        end

        def resume_interactive_queue
          @turn_queue_mutex.synchronize do
            @turn_queue_paused = false
            @turn_cancel_requested = false
            start_interactive_queue_worker_locked if !@turn_worker&.alive? && @turn_queue.any?
          end
          count = interactive_queue_count
          terminal_puts(count.positive? ? "queue0: resuming, #{count} queued" : "queue0: no queued messages")
          nil
        end

        def host_refusal_for(line)
          Master::Ground::HostBudget.refuse_heavy_prompt?(line)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "CLI.host_refusal_for")
          "host budget unavailable, #{e.class}: #{e.message}"
        end
      end

      include ReplFlow
    end
  end
end
