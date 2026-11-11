# frozen_string_literal: true

require "tty-screen"
require_relative "../../face"
require_relative "resource_load"
require_relative "../stream_accumulator"
require_relative "../../voice/typography"

module Master
  module CLI
    class Session
      TICK_SECONDS = 0.18
      FAST_TICK_SECONDS = 0.04
      SPINNER_FRAMES = [".", ":", ";", "o", "O", "0", "@", "0", "O", "o", ";", ":", ".", "+", "x", "*"].freeze
      SPIN_PROBE_SECONDS = 0.5
      # Below this the row stays plain; the ramp runs amber to red above it.
      SPIN_COLOR_START = 0.35
      SPIN_WHITE_HOT_START = 0.92
      STAGE_EVENTS = {
        "infer:resolved" => "infer",
        "infer:confidence" => "infer",
        "infer:rejected" => "infer",
        "route:resolved" => "route",
        "llm:routed" => "model",
      }.freeze

      private

      # One line that repaints while a turn runs, and above it the turn as a
      # dmesg: each model call, file, command and request the turn makes, as a
      # unit attached to its parent. Routine bus events stay in the event log;
      # one /fix reading publishes about 28,700 of them.
      # The spinner may use the reserved row only while the prompt and draft
      # fit on one physical terminal row. Long drafts disable row painting rather
      # than risk cursor motion into text owned by Reline.
      def activity_row_safe_to_draw?
        return false unless @activity_row_reserved && @reading_input
        return false unless $stdin.tty? && $stdout.tty?

        width = TTY::Screen.width.to_i
        buffer = Reline.line_buffer.to_s
        prompt = @active_prompt.to_s
        width.positive? && prompt.length + buffer.length * 2 + 2 < width
      rescue StandardError
        false
      end

      # Called under Dmesg's terminal mutex. Save and restore the input cursor
      # while clearing the preceding row; if the draft wraps, abandon the row.
      def clear_reserved_activity_row(target)
        return false unless @activity_row_reserved

        safe = activity_row_safe_to_draw? && target.respond_to?(:tty?) && target.tty?
        if safe
          target.print("\e7\e[1A\r\e[K\e8")
          target.flush if target.respond_to?(:flush)
        end
        @activity_row_reserved = false
        safe
      rescue StandardError => e
        @activity_row_reserved = false
        Master::Ground::Swallow.log(e, context: "cli.activity_row.clear", event_bus: @refs.bus)
        false
      end

      def print_thinking_indicator
        init_thinking_state!
        return unless $stdout.tty?

        @spin_thread = Thread.new do
          loop do
            # The spinner owns its row: guarded off, or every tick would step
            # below the draft first.
            Master::Trace::Dmesg.terminal_write(guard: false) { |target| paint_spin_row(target) }
            break if @spin_paused

            sleep spin_pause(@spin_intensity)
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.spinner", event_bus: @refs.bus)
        end
      end

      # One repaint under the dmesg terminal mutex; @spin_paused stops the
      # thread when the fold's ask held the row. All of the spinner's mutable
      # state advances here; the helpers below stay pure.
      def paint_spin_row(target)
        paused, stage = @think_mutex.synchronize { [@think_paused, @think_stage.to_s] }
        @spin_paused = paused
        return if paused

        @spin_intensity, @spin_probe_at = probe_intensity(@spin_intensity, @spin_probe_at)
        line = one_row(spin_line(stage, SPINNER_FRAMES.fetch(@spin_frame % SPINNER_FRAMES.length)))
        @spin_frame += 1

        draw_spin_row(target, spin_tinted(line, @spin_intensity))
        target.flush
      end

      # The spinner's line: frame, stage word, elapsed time and any queue.
      def spin_line(stage, name)
        stage = "working" if stage.empty?
        detail = stage == "intake" ? %q{ \_} : " #{elapsed_seconds}s"
        "#{name} #{stage}#{detail}#{spin_suffix}"
      end

      def spin_tinted(line, intensity)
        tint = spinner_tint(intensity)
        return line unless tint

        if intensity >= SPIN_WHITE_HOT_START && !line.empty?
          glyph = line[0]
          rest = line[1..].to_s
          "\e[1;38;2;255;255;255m#{glyph}\e[0m#{tint}#{rest}\e[0m"
        else
          "#{tint}#{line}\e[0m"
        end
      end

      def draw_spin_row(target, line)
        if @reading_input
          # A reserved row above Reline's prompt keeps the animation
          # visible without painting over the user's editable draft.
          target.print("\e7\e[1A\r\e[K#{line}\e8") if activity_row_safe_to_draw?
        elsif !@turn_current_started
          target.print("\r\e[K#{line}")
        end
      end

      # Busy-turn queue receipts ride the spinner row (Johann 2026-11-07:
      # separate queue0 lines churned the display under the spinner).
      def spin_suffix
        queued = @turn_queue_mutex.synchronize { @turn_queue.size } if @turn_worker&.alive?
        queued.to_i.positive? ? " - #{queued} queued" : ""
      end

      # One ps snapshot per SPIN_PROBE_SECONDS; between them the last score
      # sets speed and color.
      def probe_intensity(intensity, probe_at)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return intensity, probe_at if now < probe_at

        [ResourceLoad.turn, now + SPIN_PROBE_SECONDS]
      end

      # More work spins the star faster and turns it redder: TICK_SECONDS and
      # no tint at rest, FAST_TICK_SECONDS and full red at intensity 1.
      def spin_pause(intensity)
        normalized = Float(intensity).clamp(0.0, 1.0)
        span = TICK_SECONDS - FAST_TICK_SECONDS
        FAST_TICK_SECONDS + span * (1.0 - normalized)
      end

      # The tint reads its amber-to-red stops from face_interface.ascii
      # (spinner_tint) — colour is a token fact, not a constant here. The
      # channels interpolate linearly between the stops; below the threshold
      # the row stays plain, and a missing or malformed token degrades to
      # plain too rather than raising in the paint path.
      def spinner_tint(intensity)
        return unless intensity > SPIN_COLOR_START

        stops = Master::Face::Contract.spinner_tint || {}
        from = Master::Face::Contract.rgb_channels(stops["from"])
        to = Master::Face::Contract.rgb_channels(stops["to"])
        return unless from && to

        ramp = (intensity - SPIN_COLOR_START) / (1.0 - SPIN_COLOR_START)
        channels = from.zip(to).map { |a, b| (a + (b - a) * ramp).round }
        "\e[38;2;#{channels.join(';')}m"
      end

      def init_thinking_state!
        @think_mutex = Mutex.new
        @think_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @think_paused = false
        @think_stage = "intake"

        @spin_frame = 0
        @spin_intensity = 0.0
        @spin_probe_at = 0.0
        @spin_paused = false

        @activity&.reset!
        # `**`: a single star is colon-free names only, and every stage event has one.
        @think_sub = @refs.bus&.subscribe("**") { |payload| update_think_stage(payload) }
        @unit_sub = @refs.logging.listen { |line| print_unit_line(line) } if units_console?
      end

      # The fold stops to ask a person about a push, a hard reset or a deploy,
      # and a terminal the operator is typing into is a person. The operator
      # said approval belongs there, so the interactive session answers; the
      # daemon, a pipe and the web face build no asker and still refuse.
      #
      # Carried as a fiber local because the turn runs on its own thread and
      # CoreBridge builds the World deep below it. A thread spawned inside the
      # turn inherits fiber storage, so the asker answers only on the thread
      # the turn owns: a standing order firing mid-turn runs unattended and is
      # refused, as it is everywhere else.
      def terminal_ask(owner)
        return unless $stdin.tty? && $stdout.tty?

        lambda do |prompt:, options: nil, **|
          next "no: asked off the terminal turn" unless Thread.current == owner

          answer_at_terminal(prompt, options:)
        end
      end

      # y/N, with the spinner held still so the question is not painted over.
      # Anything but a yes is a no, which Core::Fold decides.
      # Keep the established direct approval reader for synchronous turns. A
      # background turn must not compete with Reline for stdin, so it refuses
      # an approval-dependent operation safely while the next prompt is active.
      # In an asynchronous interactive turn, Reline remains the sole owner
      # of stdin. Hand approval requests back to the main input loop instead of
      # starting a second reader that can steal a draft.
      def answer_at_terminal(prompt, options: nil)
        choices = normalize_ask_options(options)
        return auto_approved(prompt, choices) if auto_approve?

        if @turn_worker&.alive? && Thread.current == @pipeline_thread && $stdin.tty? && $stdout.tty?
          request = { answer: nil, choices: }
          @terminal_ask_mutex.synchronize { @pending_terminal_ask = request }
          label = @refs.renderer.render("ask0: #{prompt}", mode: :dmesg)
          rows = [label, *choices.each_with_index.map { |choice, index| "  #{index + 1}) #{choice.fetch(:name)}" }]
          rows << (choices.empty? ? "enter /approve or /deny; other input stays queued" : "enter /approve N or /deny; other input stays queued")
          terminal_puts(rows.join("\n"))
          answer = @terminal_ask_mutex.synchronize do
            @terminal_ask_cv.wait(@terminal_ask_mutex) while @pending_terminal_ask.equal?(request) && request[:answer].nil?
            request[:answer]
          end
          return answer.to_s.strip if choices.empty?
          index = Integer(answer, exception: false)
          choice = index && choices[index - 1]
          return choice ? choice.fetch(:value).to_s : ""
        end

        @think_mutex&.synchronize { @think_paused = true }
        terminal_print("\r\e[K")
        return answer_choice_at_terminal(prompt, choices) unless choices.empty?
        terminal_print("#{@refs.renderer.render("ask0: #{prompt} [y/N]", mode: :dmesg)} ")
        $stdin.gets.to_s.strip
      ensure
        if defined?(request) && request
          @terminal_ask_mutex.synchronize do
            @pending_terminal_ask = nil if @pending_terminal_ask.equal?(request)
            @terminal_ask_cv.broadcast
          end
        end
        @think_mutex&.synchronize { @think_paused = false }
      end

      # The operator decided the session approves on its own; the line stays in the log.
      def auto_approve?
        config = @refs.respond_to?(:config) ? @refs.config : nil
        (config.respond_to?(:fetch) ? config.fetch("auto_approve", true) : true) != false
      end

      def auto_approved(prompt, choices)
        terminal_puts(@refs.renderer.render("ask0: auto-approved, #{prompt}", mode: :dmesg))
        return "yes" if choices.empty?

        (choices.find { |choice| choice.fetch(:value) == "approve" } || choices.first).fetch(:value).to_s
      end

      def terminal_ask_pending?
        @terminal_ask_mutex.synchronize { !@pending_terminal_ask.nil? }
      end

      def answer_pending_terminal_ask(line)
        text = line.to_s.strip
        @terminal_ask_mutex.synchronize do
          request = @pending_terminal_ask
          return false unless request

          if text.match?(%r{\A/deny\z}i)
            request[:answer] = "no"
          elsif text.match?(%r{\A/approve(?:\s+.*)?\z}i)
            value = text.sub(%r{\A/approve}i, "").strip
            request[:answer] = value.empty? && request[:choices].empty? ? "yes" : value
          else
            return false
          end
          @terminal_ask_cv.broadcast
          true
        end
      end

      # LLMs may serialize approval choices as an array, a single choice object,
      # or a name => value map. Normalize those shapes before indexing; an
      # unnormalized Hash was enumerated as key/value pairs and raised a
      # Symbol-to-Integer TypeError when the renderer treated an Array as a Hash.
      def normalize_ask_options(options)
        entries = case options
                  when Array then options
                  when Hash
                    if %i[name label value].any? { |key| options.key?(key) || options.key?(key.to_s) }
                      [options]
                    else
                      options.map { |name, value| { name:, value: } }
                    end
                  else []
                  end

        entries.filter_map do |entry|
          case entry
          when Hash
            name = entry[:name] || entry["name"] || entry[:label] || entry["label"]
            value = entry[:value] || entry["value"] || name
            next if name.nil?

            { name: name.to_s, value: value.to_s }
          when String, Symbol
            { name: entry.to_s, value: entry.to_s }
          end
        end
      end

      def answer_choice_at_terminal(prompt, options)
        choices = options.each_with_index.map { |option, index| "#{index + 1}) #{option.fetch(:name)}" }
        terminal_write do |target|
          target.print @refs.renderer.render("ask0: #{prompt}", mode: :dmesg)
          target.print "\n  #{choices.join("\n  ")}\n> "
          target.flush
        end
        selected = $stdin.gets.to_s.strip
        index = Integer(selected, exception: false)
        option = index && options[index - 1]
        option ? option.fetch(:value).to_s : ""
      end

      # The spinner stops when a reply streams; detailed events still print.
      def stop_thinking_indicator
        @think_mutex&.synchronize { @think_paused = true }
        @spin_thread&.join
        @spin_thread = nil
        @think_sub&.call
        @think_sub = nil
        if @activity_row_reserved
          Master::Trace::Dmesg.terminal_write(guard: false) { |target| clear_reserved_activity_row(target) }
        elsif $stdout.tty?
          terminal_print("\r\e[K")
        end
      end

      # Detailed dmesg is the default; MASTER_CLI_QUIET=1 is the opt-out.
      def verbose_output?
        ENV["MASTER_CLI_QUIET"] != "1"
      end

      def units_console?
        @refs.logging.respond_to?(:listen) && Master::Trace::Dmesg.enabled?
      end

      def close_unit_console
        @unit_sub&.call
        @unit_sub = nil
      end

      def update_think_stage(payload)
        event = payload[:event].to_s
        @activity&.record(event, payload)
        stage = stage_for(event, payload)
        @think_mutex&.synchronize { @think_stage = stage } if stage
      end

      def stage_for(event, payload)
        return stage_with_detail(event, payload) if event.start_with?("stage:")
        return payload[:stage].to_s.downcase if event == "pipeline:stage_start"

        STAGE_EVENTS[event]
      end

      # "stage:*" events name their own unit and may carry a live detail — the
      # media lane's download fraction, for one. The row reads "mov0 34% of
      # 667.6MB — Title"; one_row keeps it inside the screen's width.
      def stage_with_detail(event, payload)
        name = event.delete_prefix("stage:")
        detail = payload[:detail].to_s.strip
        detail.empty? ? name : "#{name} #{detail}"
      end

      # What is worth saying out loud while a pass runs. A pass prints hundreds
      # of unit lines and speaking each would be a torrent; these are the ones a
      # person waiting for it would want called out — a reading finished, a pass
      # of repairs counted, the council's verdict, the pass itself ending.
      # Spoken as they happen, so the reply at the end has only its footer left
      # to say instead of the whole log.
      MILESTONE = /\A(?:obs\d+: done|scan\d+: (?:done|pass \d)|fix\d+: pass \d|crit\d+: |review\d+: (?:complete|incomplete))/

      # A line the units console prints. While the draft is being edited the
      # guard moves the line to a row of its own below the cursor and the
      # editable line repaints afterwards; while the turn runs inline the
      # legacy rows stand — clear the row, print, as the line always did.
      def print_unit_line(line)
        return unless Master::Trace::Dmesg.enabled?

        Master::Voice::Playback.speak(line) if line.match?(MILESTONE) && !Master::Trace::Dmesg.log_voice_active?
        return unless verbose_output?

        io = $stdout.isatty ? $stdout : $stderr
        @think_mutex&.synchronize { @think_stage = line[/\A[^\s:]+/] }
        Master::Trace::Dmesg.terminal_write(io:) do |target|
          unit_line_rows(io, target)
          target.puts @refs.renderer.render(line, mode: :dim)
          target.flush
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_unit_line", event_bus: @refs.bus)
      end

      # The unit row is the guard's job while a draft is edited (plain payload
      # below the cursor, repaint afterwards). Only the inline turn keeps the
      # legacy rows: give up the spinner's row, clear, then the line prints.
      def unit_line_rows(io, target)
        return if io.equal?($stdout) && @reading_input && tty_target?(target)

        clear_reserved_activity_row(target) if io.equal?($stdout)
        target.print "\r\e[K" if tty_target?(target)
      end

      # The spinner repaints with \r\e[K, which clears one row. A line wider
      # than the screen wraps onto a second row that nothing clears, and every
      # tick left another copy behind it. Unit lines are printed once and may
      # wrap. The spinner's own row cuts at a word's edge on one ellipsis.
      def one_row(text)
        width = TTY::Screen.width - 1
        return text unless width.positive? && text.length > width

        Master::Voice::Typography.ellipsis(text, width)
      rescue StandardError
        text
      end

      def elapsed_seconds
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @think_t0.to_f).floor
      end

      def build_stream_handler(buffer, &on_text)
        Master::CLI::StreamAccumulator.new(buffer, &on_text)
      end
    end
  end
end
