# frozen_string_literal: true

require "tty-screen"
require "uri"
require_relative "resource_load"
require_relative "../stream_accumulator"
require_relative "../../voice/typography"

module Master
  module CLI
    class Session
      TICK_SECONDS = 0.18
      FAST_TICK_SECONDS = 0.10
      # Fixed-width ASCII frames keep the spinner on one terminal cell.
      SPINNER_FRAMES = ["*", "+", "x", "+"].freeze
      SPIN_PROBE_SECONDS = 0.5
      ACTIVITY_REARM_IDLE_S = 0.45
      TOOL_ACTIVITY_HOLD_SECONDS = 1.2
      STAGE_EVENTS = {
        "infer:resolved" => "infer",
        "infer:confidence" => "infer",
        "infer:rejected" => "infer",
        "route:resolved" => "route",
        "llm:routed" => "model",
        "llm:send" => "waiting",
        "llm:stream_started" => "streaming",
        "user:interrupt" => "stopping",
      }.freeze

      private

      module ThinkingIndicator
        private

        # One line that repaints while a turn runs, and above it the turn as a
        # dmesg: each model call, file, command and request the turn makes, as a
        # unit attached to its parent. Routine bus events stay in the event log;
        # one /fix reading publishes about 28,700 of them.
        # The spinner may use the reserved row only while the prompt and draft
        # fit on one physical terminal row. Long drafts disable row painting rather
        # than risk cursor motion into text owned by Reline.
        def activity_row_safe_to_draw?
          @activity_row_reserved && draft_row_safe_to_reuse?($stdout)
        end

        # Reuse the editable row for a dmesg line when the draft fits on one
        # physical row. A wrapped/multiline draft keeps the conservative step
        # below it so no owned text is overwritten.
        def draft_row_safe_to_reuse?(target)
          return false unless @reading_input && target.equal?($stdout)
          return false unless $stdin.tty? && target.respond_to?(:tty?) && target.tty?

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
          reserve_activity_row_after_quiet(target)
          activity = tool_activity_line
          line = one_row(spin_line(stage, SPINNER_FRAMES.fetch(@spin_frame % SPINNER_FRAMES.length), activity:))
          @spin_frame += 1

          draw_spin_row(target, spin_tinted(line, @spin_intensity))
          target.flush
        end

        # The spinner is the live activity surface: a concise stage while the
        # model is thinking, or the actual tool action while it is operating.
        # It never prints prompts, queries, command text or returned content.
        def spin_line(stage, frame, activity: nil)
          description = activity.to_s.empty? ? stage.to_s : activity.to_s
          suffix = spin_suffix
          [frame, description, suffix.empty? ? nil : suffix].compact.reject(&:empty?).join(" ")
        end

        def update_tool_activity(tool:, args:, state:, invocation_id: nil, elapsed_ms: nil)
          label = safe_tool_activity_label(tool, args)
          return if label.empty?

          now = monotonic_now
          @think_mutex&.synchronize do
            @think_active_tools ||= {}
            key = invocation_id.to_s
            key = "#{tool}:#{label}" if key.empty?
            if state.to_s == "started"
              @think_active_tools[key] = { label:, started_at: now }
              @think_last_tool_activity = nil
            else
              active = @think_active_tools.delete(key)
              label = active[:label] if active
              @think_last_tool_activity = { label:, state: state.to_s, at: now, elapsed_ms: }
            end
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.tool_activity", event_bus: @refs&.bus)
          nil
        end

        def tool_activity_line
          now = monotonic_now
          @think_mutex&.synchronize do
            active = (@think_active_tools || {}).values.last
            if active
              "#{active[:label]} ..."
            else
              last = @think_last_tool_activity
              next unless last && now - last[:at] <= TOOL_ACTIVITY_HOLD_SECONDS

              state = last[:state].to_s == "done" ? "done" :
                      last[:state].to_s == "blocked" ? "blocked" : "failed"
              duration = last[:elapsed_ms].to_f >= 1_000 ? " (#{format("%.1fs", last[:elapsed_ms].to_f / 1_000)})" : ""
              "#{last[:label]} #{state}#{duration}"
            end
          end
        rescue StandardError
          nil
        end

        def safe_tool_activity_label(tool, args)
          values = args.respond_to?(:to_h) ? args.to_h : {}
          read = ->(key) { values[key] || values[key.to_s] }
          name = tool.to_s.gsub(/([a-z0-9])([A-Z])/) { "#{Regexp.last_match(1)}_#{Regexp.last_match(2)}" }.downcase

          case name
          when "read_file" then "read #{safe_activity_path(read.call(:path)) || "file"}"
          when "list_dir" then "list #{safe_activity_path(read.call(:path)) || "workspace"}"
          when "tree" then "map #{safe_activity_path(read.call(:path)) || "workspace"}"
          when "write_file" then "write #{safe_activity_path(read.call(:path)) || "file"}"
          when "str_replace", "replace", "ast_edit" then "edit #{safe_activity_path(read.call(:path)) || "file"}"
          when "search_files"
            path = safe_activity_path(read.call(:path))
            "search files#{path ? " in #{path}" : ""}"
          when "search_knowledge" then "search local knowledge"
          when "symbol_lookup" then "find symbol"
          when "zsh" then "run shell"
          when "git_context"
            operation = safe_activity_token(read.call(:operation))
            path = safe_activity_path(read.call(:path))
            ["git", operation, path].compact.join(" ")
          when "web_search" then "search web"
          when "web_fetch" then "fetch #{safe_activity_host(read.call(:url)) || "website"}"
          when "browser"
            action = safe_activity_token(read.call(:action))
            host = safe_activity_host(read.call(:url))
            ["browser", action, host].compact.join(" ")
          when "dynamic_http" then "HTTP request"
          when "githubrepominer", "github_repo_miner" then "search GitHub"
          when "arxivresearch", "arxiv_research" then "search arXiv"
          when "youtubetranscript", "youtube_transcript" then "fetch transcript"
          when "lovdata" then "look up Lovdata"
          when "nmap" then "network scan"
          when "ask_llm" then "ask submodel"
          when "plugin_observe" then "inspect plugin"
          else
            safe = name.gsub(/[^a-z0-9_]/, "").tr("_", " ")
            safe.empty? ? "use tool" : safe
          end.then { |label| Master::Voice::Typography.ellipsis(label, 54) }
        rescue StandardError
          "use tool"
        end

        def safe_activity_token(value)
          token = value.to_s.downcase
          token.match?(/\A[a-z][a-z0-9_-]{0,19}\z/) ? token : nil
        end

        def safe_activity_path(value)
          raw = value.to_s.strip.tr("\\", "/")
          return "workspace" if raw == "." || raw.empty?
          return "protected file" if raw.start_with?("/") || raw.match?(/\A[A-Za-z]:/)

          parts = raw.split("/").reject(&:empty?)
          return "protected file" if parts.empty? || parts.any? do |part|
            part == "." || part == ".." || part.start_with?(".") ||
              part.match?(/secret|token|password|credential|private|api.?key|id_rsa/i)
          end

          Master::Voice::Typography.ellipsis(parts.join("/"), 42)
        end

        def safe_activity_host(value)
          uri = URI.parse(value.to_s)
          return unless %w[http https].include?(uri.scheme.to_s.downcase)

          host = uri.host.to_s.downcase
          host.match?(/\A[a-z0-9.:-]{1,180}\z/) ? host : nil
        rescue URI::InvalidURIError
          nil
        end

        def spin_tinted(line, _intensity)
          tint = spinner_tint(nil)
          return line unless tint

          glyph = line[/\A[*+x]/]
          return line unless glyph

          "#{tint}#{glyph}\e[0m#{line.delete_prefix(glyph)}"
        end

        # Reclaim the spinner row only after a burst of dmesg output has
        # settled. Fast model failover should read like an OpenBSD log, not a
        # stack of empty rows between device reports.
        def reserve_activity_row_after_quiet(target)
          return unless @reading_input && @turn_worker&.alive?
          return if @activity_row_reserved || @turn_queue_paused || @closed

          last = @last_foreign_write_at
          return unless last && monotonic_now - last >= ACTIVITY_REARM_IDLE_S

          target.puts
          target.flush if target.respond_to?(:flush)
          @activity_row_reserved = true
          redraw_active_input
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.activity_row.rearm", event_bus: @refs.bus)
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def draw_spin_row(target, line)
          if @reading_input
            # A reserved row above Reline's prompt keeps the animation
            # visible without painting over the user's editable draft.
            target.print("\e7\e[1A\r\e[K#{line}\e8") if activity_row_safe_to_draw?
          else
            # Once a queued turn starts, it still owns a clean status row. The
            # next dmesg write clears this row first; the spinner paints again
            # below that event on its next tick.
            target.print("\r\e[K#{line}")
            @spinner_row_visible = true
          end
        end

        # Busy-turn queue receipts ride the spinner row (Johann 2026-11-07:
        # separate queue0 lines churned the display under the spinner).
        def spin_suffix
          queued = @turn_queue_mutex.synchronize { @turn_queue.size } if @turn_worker&.alive?
          queued.to_i.positive? ? " - #{queued} queued" : ""
        end

        # One host load-average sample per SPIN_PROBE_SECONDS; the normalized
        # CPU load sets cadence only. The glyph colour is invariant.
        def probe_intensity(intensity, probe_at)
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return intensity, probe_at if now < probe_at

          [ResourceLoad.cpu_load, now + SPIN_PROBE_SECONDS]
        end

        # Higher CPU load spins the star faster: slow at idle, fast at saturation.
        # Colour is intentionally not coupled to resource pressure.
        def spin_pause(intensity)
          normalized = Float(intensity || 0.0).clamp(0.0, 1.0)
          span = TICK_SECONDS - FAST_TICK_SECONDS
          FAST_TICK_SECONDS + span * (1.0 - normalized)
        end

        # Fixed white keeps the ASCII glyph legible without making telemetry
        # look like an alert. CPU intensity is deliberately ignored.
        def spinner_tint(_intensity)
          return if !ENV["NO_COLOR"].to_s.empty? || ENV["TERM"].to_s.casecmp("dumb").zero?

          "\e[38;2;255;255;255m"
        end

        def init_thinking_state!
          @think_mutex = Mutex.new
          @think_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @think_paused = false
          @think_stage = "intake"
          @think_stopping = false

          @spin_frame = 0
          @spinner_row_visible = false
          @spin_intensity = nil
          @spin_probe_at = 0.0
          @spin_paused = false

          @activity&.reset!
          @think_active_tools = {}
          @think_last_tool_activity = nil
          @tool_activity_sink = ->(**details) { update_tool_activity(**details) }
          Master::Trace::Dmesg.set_activity_sink(@tool_activity_sink)
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
          Master::Trace::Dmesg.clear_activity_sink(@tool_activity_sink) if @tool_activity_sink
          @tool_activity_sink = nil
          if @activity_row_reserved
            Master::Trace::Dmesg.terminal_write(guard: false) { |target| clear_reserved_activity_row(target) }
          elsif $stdout.tty?
            terminal_print("\r\e[K")
          end
          @spinner_row_visible = false
        end

        # Routine unit traffic is diagnostic, not the interactive default.
        # --verbose/--trace/--detail opt back in through Dmesg's single policy.
        def verbose_output?
          Master::Trace::Dmesg.verbose? && ENV["MASTER_CLI_QUIET"] != "1"
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
          if %w[llm:send llm:stream_started pipeline:stage_start].include?(event)
            @think_mutex&.synchronize { @think_last_tool_activity = nil }
          end
          stage = stage_for(event, payload)
          @think_mutex&.synchronize do
            if event == "user:interrupt"
              @think_stopping = true
              @think_stage = stage || "stopping"
            elsif !@think_stopping && stage
              @think_stage = stage
            end
          end
        end

        def stage_for(event, payload)
          return stage_with_detail(event, payload) if event.start_with?("stage:")
          return payload[:stage].to_s.downcase if event == "pipeline:stage_start"
          return provider_outcome_stage(payload) if event == "llm:provider_outcome"

          stage = STAGE_EVENTS[event]
          return stage unless %w[llm:send llm:stream_started].include?(event)

          provider_stage(stage, payload[:model])
        end

        # Provider outcomes are per-attempt, not whole-turn outcomes. Name a
        # timeout or completed response while fallback/tools continue; the next
        # llm:send replaces it with the next actual provider.
        def provider_outcome_stage(payload)
          stage = case payload[:status].to_s
                  when "success" then "received"
                  when "timeout" then "timeout"
                  when "rate_limit" then "rate limit"
                  when "quota_exceeded" then "quota"
                  when "llm_call_failure", "provider_error", "failure" then "provider error"
                  else "provider status"
                  end
          provider_stage(stage, payload[:model])
        end

        # The dispatch event names the lane that actually passed the send gate,
        # not the route's earlier candidate. Keep the spinner useful on failover
        # without printing a long model id or untrusted terminal control text.
        def provider_stage(stage, model)
          provider = Master::Io::LaneSelection.provider(model).to_s
          provider = provider.gsub(/[^A-Za-z0-9_.:-]/, "")[0, 18]
          provider.empty? ? stage : "#{stage} #{provider}"
        rescue StandardError
          stage
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

        def build_stream_handler(buffer, &on_text)
          Master::CLI::StreamAccumulator.new(buffer, &on_text)
        end
      end

      include ThinkingIndicator
      MILESTONE = ThinkingIndicator::MILESTONE
    end
  end
end
