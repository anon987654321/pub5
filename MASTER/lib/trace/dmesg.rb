# frozen_string_literal: true

require "set"
# DmesgUnit names each event component's unit. It lives in logging.rb, and no
# autoload reaches it by that name.
require_relative "logging"
require_relative "../voice/typography"

module Master
  module Trace
    # OpenBSD dmesg-style kernel lines for operator progress.
    # Shape: "unitN at parent: detail" / "unitN: status". Prose, not key=value:
    # "scan0: 3 violations in 2 files", as the kernel says "sd0: 244198MB".
    # Config: data/console.yml#dmesg (enabled: true). Normal is the configured default; verbose and trace are explicit.
    # ENV MASTER_DMESG accepts 0, quiet, normal, verbose, trace or everything.
    # --detail opts into bounded terminal payloads; ordinary event output stays redacted.
    #
    # This shape is the CLI's whole style guide: append-only, one line per fact,
    # no banner. The machine-readable form of the same facts is the event bus
    # and the JSONL ledgers under runtime/, not a second presenter here.
    module Dmesg
      module_function

      LEVELS = %w[quiet normal verbose trace everything].freeze
      TERMINAL_WRITE_MUTEX = Mutex.new
      @draft_guard = nil

      def enabled?
        return false if @verbosity_override == "quiet"
        return false if ENV["MASTER_QUIET"] == "1"

        env = ENV["MASTER_DMESG"].to_s.downcase
        return false if env == "0" || env == "quiet"
        return true if %w[1 normal verbose trace everything].include?(env)

        cfg.fetch("enabled", true) != false
      end

      def verbosity
        override = @verbosity_override
        return override if override

        env = ENV["MASTER_DMESG"].to_s.downcase
        return "quiet" if env.empty? && ENV["MASTER_QUIET"] == "1"
        return normalize_verbosity(env) unless env.empty?

        normalize_verbosity(cfg.fetch("verbosity", "verbose"))
      end

      def verbose?
        %w[verbose trace everything].include?(verbosity)
      end

      def trace?
        %w[trace everything].include?(verbosity)
      end

      # "everything" is trace plus the separately gated detail channel.
      # MASTER_DMESG_DETAIL is an explicit consent switch for terminal payloads.
      def detail_enabled?
        return true if verbosity == "everything"

        %w[1 true yes on].include?(ENV["MASTER_DMESG_DETAIL"].to_s.downcase)
      end

      # Bind the numbered unit emitted by the event console to the operation
      # that follows it. Fiber-local storage keeps concurrent calls distinct.
      def bind_detail_unit(kind, unit)
        (Fiber[:master_dmesg_detail_units] ||= {})[kind.to_s] = unit.to_s
      end

      def clear_detail_unit(kind)
        Fiber[:master_dmesg_detail_units]&.delete(kind.to_s)
      end

      def detail_unit(kind)
        Fiber[:master_dmesg_detail_units]&.fetch(kind.to_s, nil) || kind.to_s
      end

      def with_verbosity(level)
        previous = @verbosity_override
        @verbosity_override = normalize_verbosity(level)
        yield
      ensure
        @verbosity_override = previous
      end

      def with_log_voice
        previous = @log_voice_active
        @log_voice_active = true
        yield
      ensure
        @log_voice_active = previous
      end

      def log_voice_active?
        @log_voice_active == true
      end

      def log_voice_spoken_recently?(text, window: 8.0)
        clean = text.to_s.gsub(/\s+/, " ").strip
        return false if clean.empty?

        recent = @recent_log_voice
        return false unless recent

        timestamp, spoken = recent
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - timestamp) <= window && spoken == clean
      rescue StandardError
        false
      end

      def cfg
        @cfg ||= begin
          section = Master.config_section("dmesg")
          section.is_a?(Hash) ? section : { "enabled" => true }
        rescue StandardError
          { "enabled" => true }
        end
      end

      def reload!
        @cfg = nil
        cfg
      end

      def normalize_verbosity(value)
        value = value.to_s.downcase
        value = "normal" if value == "1" || value.empty?
        LEVELS.include?(value) ? value : "normal"
      end

      def attach(unit, parent, detail = nil, io: $stdout)
        line = detail.to_s.empty? ? "#{unit} at #{parent}" : "#{unit} at #{parent}: #{detail}"
        emit(line, io:)
      end

      def status(unit, msg, io: $stdout)
        Master::Fix::RunBudget.note_output(unit, msg) if defined?(Master::Fix::RunBudget)
        emit("#{unit}: #{msg}", io:)
      end

      # A subordinate terminal-only channel for payloads that the event ledger
      # intentionally redacts. It is silent unless explicitly enabled; it never
      # publishes to the bus, ring buffer or JSONL. Detail is not narrated.
      def detail(unit, text, io: $stdout, indent: nil, style: nil)
        return unless detail_enabled? && enabled?

        settings = cfg
        indent = Integer(indent || settings.fetch("detail_indent", 2)).clamp(0, 16)
        maxch = Integer(settings.fetch("detail_max_chars", 240)).clamp(1, 4_000)
        maxln = Integer(settings.fetch("detail_max_lines", 8)).clamp(1, 100)
        marker = settings.fetch("detail_truncate_marker", "…").to_s
        subordinate(detail_unit(unit), text, io:, indent:, style:, maxch:, maxln:, marker:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.detail")
        nil
      end

      # A multi-line message keeps its lines. emit flattens whitespace by
      # design — one fact per line means the caller owns the lines — so a
      # structured report hands its lines over one by one, each attached to
      # the same unit, the way Report.print attaches prose to a command's
      # unit. The fold's evidence read as one 200-character ribbon when this
      # did not exist; flattened by emit, then truncated again by the caller,
      # twice destroyed.
      def block(unit, text, io: $stdout)
        lines = text.to_s.scrub.delete("\r").split("\n", -1)
        lines.each_with_index do |line, index|
          body = line.strip
          next emit("", io:) if body.empty?

          if index.zero?
            status(unit, body, io:)
          else
            emit("#{unit}: #{body}", io:)
          end
        end
        nil
      end

      # A line that ends in what is known about its gap: whether it resolves on
      # its own, what checking costs, and whose call it is. No gap, no clause.
      def gap(unit, msg, gap, io: $stdout)
        status(unit, gap ? "#{msg}, #{gap.clause}" : msg, io:)
      end

      # Finished command and stage reports use the same grammar as live events.
      # Existing dmesg lines pass through unchanged; plain lines attach to one
      # unit instead of inventing headings, gutters or column alignment.
      module Report
        COMMAND_UNITS = {
          "fix" => "fix0", "review" => "review0", "critique" => "crit0",
          "status" => "status0", "help" => "help0", "model" => "model0",
          "plugin" => "plugin0", "android" => "android0", "ios" => "ios0",
          "device" => "device0", "voice" => "voice0",
          "pair" => "pair0", "owner" => "owner0", "wake" => "wake0",
          "doctor" => "doctor0", "rules" => "rules0", "snapshot" => "snapshot0",
          "why" => "why0", "session" => "session0", "undo" => "undo0",
          "clear" => "cli0", "orders" => "orders0", "soul" => "soul0"
        }.freeze

        UNIT_RE = /\A[a-z][a-z0-9_]*\d+(?: at [a-z][a-z0-9_]*\d+)?:/

        module_function

        def command(command, text, parent: "master0")
          word = command.to_s.strip.split(/\s+/, 2).first.to_s.delete_prefix("/").downcase
          unit = COMMAND_UNITS.fetch(word) { safe_unit(word) }
          render(unit:, parent:, text:)
        end

        def render(unit:, parent:, text:)
          source = text.to_s.scrub.gsub(ANSI, "").delete("\r")
          return "" if source.strip.empty?

          lines = []
          attached = false
          source.lines.each do |raw|
            line = raw.chomp.strip
            if line.empty?
              lines << "" unless lines.empty? || lines.last.empty?
              attached = false
              next
            end

            if UNIT_RE.match?(line)
              lines << line
              attached = true
            elsif attached
              lines << "#{unit}: #{line}"
            else
              lines << "#{unit} at #{parent}: #{line}"
              attached = true
            end
          end
          lines.join("\n").strip
        end

        def print(command, text, parent: "master0", io: $stdout)
          rendered = render(unit: command_unit(command), parent:, text:)
          rendered.lines.each do |line|
            line = line.chomp
            if line.empty?
              io.puts
            else
              Dmesg.emit(line, io:, force: true)
            end
          end
          io.flush if io.respond_to?(:flush)
          rendered
        end

        def command_unit(command)
          word = command.to_s.strip.split(/\s+/, 2).first.to_s.delete_prefix("/").downcase
          return word if word.match?(/\A[a-z][a-z0-9_]*\d+\z/)

          COMMAND_UNITS.fetch(word) { safe_unit(word) }
        end

        def safe_unit(word)
          word = word.gsub(/[^a-z0-9_]+/, "_").sub(/\A\d+/, "")
          word = "cli" if word.empty?
          "#{word}0"
        end
      end

      # Work that calls a model names itself, and the calls attach under it.
      # Fiber storage reaches the threads the work spawns, and is put back after.
      def under(unit)
        previous = Fiber[:master_unit]
        Fiber[:master_unit] = unit
        yield
      ensure
        Fiber[:master_unit] = previous
      end

      # Once per process, for a fact every lane would otherwise repeat.
      def once(unit, msg, io: $stdout)
        @once ||= {}
        line = "#{unit}: #{msg}"
        return if @once[line]

        @once[line] = true
        emit(line, io:)
      end

      # The one terminal write coordinator. Plain output, IRC notices, unit
      # events and transient status lines all take this lock; the lock is never
      # held while waiting for user input.
      #
      # An interactive session registers the draft guard — a pair of procs run
      # under this lock around every operator-facing write, so a write from any
      # lane lands below Reline's editable line and the editable line repaints
      # afterwards. Writes that are part of the draft's own machinery pass
      # guard: false and manage their rows alone. Pipe and log writers register
      # nothing, so they take the lock without the guard.
      def terminal_write(io: $stdout, guard: true)
        emit_mutex.synchronize do
          hooks = guard && @draft_guard ? @draft_guard : nil
          hooks&.first&.call(io)
          begin
            yield io
          ensure
            hooks&.last&.call(io)
          end
        end
      end

      def draft_guard = @draft_guard
      def draft_guard=(pair)
        @draft_guard = pair
      end

      # Unlike emit, subordinate lines retain newlines and leading spaces.
      # A numbered-unit prefix on every line keeps their parent relationship
      # searchable without changing normal console event grammar.
      def subordinate(unit, text, io:, indent:, style:, maxch:, maxln:, marker:)
        body = as_utf8_text(text.to_s).scrub.gsub(ANSI, "").delete("\r")
        body = body.gsub(/[[:cntrl:]&&[^\n\t]]/, "")
        total_lines = body.count("\n")
        total_lines += 1 unless body.empty? || body.end_with?("\n")
        lines = []
        body.each_line do |line|
          break if lines.size >= maxln

          lines << line
        end
        return if lines.empty?

        pad = " " * indent
        prefix = unit.to_s.empty? ? "" : "#{unit}: "
        rendered = lines.map do |line|
          flat = line.rstrip
          if flat.length > maxch
            keep = [maxch - marker.length, 0].max
            flat = "#{flat[0, keep]}#{marker}"
          end
          "#{pad}#{prefix}#{flat}"
        end
        omitted = total_lines - rendered.size
        rendered << "#{pad}#{prefix}#{marker} #{omitted} more line(s)" if omitted.positive?

        terminal_write(io:, guard: true) do |target|
          rendered.each { |line| target.puts(detail_style_line(line, style, target)) }
          target.flush if target.respond_to?(:flush)
        end
        nil
      end

      def detail_style_line(line, style, target)
        return line unless ENV["NO_COLOR"].to_s.empty?
        return line unless target.respond_to?(:tty?) && target.tty?

        colour = case style
                 when :context, :detail_hi then 244
                 when :add then 32
                 when :del then 31
                 else 240
                 end
        supports_256 = ENV["TERM"].to_s.include?("256color") ||
                       ENV["COLORTERM"].to_s.match?(/\A(?:truecolor|24bit)\z/i)
        sgr = if colour >= 100
          supports_256 ? "\e[38;5;#{colour}m" : "\e[90m"
        else
          "\e[#{colour}m"
        end
        "#{sgr}#{line}\e[0m"
      end

      # A line built from tool output can arrive as bytes. Written to a text IO under
      # bin/master's Encoding.default_internal it raised on the first non-ASCII byte.
      def as_utf8_text(text)
        return text unless text.encoding == Encoding::BINARY

        text.dup.force_encoding(Encoding::UTF_8).scrub
      end

      def emit(line, io: $stdout, force: false)
        return unless enabled? || force

        return if !force && quiet_in_turn?(line)

        text = as_utf8_text(line.to_s).gsub(/\s+/, " ").strip

        terminal_write(io:) do |target|
          target.puts(boot_paint(text, target))
          target.flush if target.respond_to?(:flush)
          # Interactive adapters redraw the prompt before another writer may
          # append a line. Pipes and ordinary log writers use no callback.
          yield if block_given?
        end
        narrate(text)
        speak_log_line(text) if log_voice_active?
        text
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.emit")
        nil
      end

      def emit_mutex = TERMINAL_WRITE_MUTEX

      # Normal mode keeps conversational turns quiet. Explicit command reports
      # force their already-rendered lines through the same presenter.
      def quiet_in_turn?(line)
        verbosity == "normal" && Fiber[:master_unit] == "master0" && line.match?(/at \w+0|llm\d+:/)
      end

      # OpenBSD's console prints the kernel white on blue and userland plain.
      # MASTER's boot is its kernel: a line emitted inside booting takes
      # console.yml#dmesg.boot_sgr on a terminal. Pipes, logs, the narrator and
      # everything after the boot get the plain text.
      def booting
        previous = @booting
        @booting = true
        yield
      ensure
        @booting = previous
      end

      def boot_paint(text, target)
        @booting ? console_paint(text, target) : text
      end

      # The session's splash is the last of the boot; it paints through this.
      # Each line on its own, so a reset never spans a newline.
      # 24-bit boot_sgr only where the terminal says it takes 24-bit colour; elsewhere
      # (the OpenBSD wscons console, tmux without RGB) each parameter is read alone,
      # 2 as faint and 0 as a reset, so boot_sgr_basic's palette colours are used.
      def console_paint(text, target)
        truecolor = ENV["COLORTERM"].to_s.match?(/\A(?:truecolor|24bit)\z/i)
        sgr = cfg.fetch(truecolor ? "boot_sgr" : "boot_sgr_basic", "").to_s
        return text if sgr.empty? || !ENV["NO_COLOR"].to_s.empty?
        return text unless defined?(target.tty?) && target.tty?

        text.to_s.split("\n", -1).map { |line| line.empty? ? line : "\e[#{sgr}m#{line}\e[0m" }.join("\n")
      end

      # Child processes may inherit terminal redraws even though their output
      # is captured by a pipe. Forward them as completed lines, never as cursor
      # control sequences interleaved with the parent's dmesg.
      NARRATED_FORWARD_LINE = /\A(?:-\s*)?(?:surface0:|coverage0:|flow:|Warnings:|Not checked:|Check errors|Failures:|inconclusive:|errored:|check\d+(?: at |:)|checks\d+ at |source\d+ at |openbsd\d+ at |rehearse\d+:|suite\d+:)/i.freeze
      NARRATED_FORWARD_FINDING = /\A-\s+\[[A-Za-z][A-Za-z0-9_:]*\].*\b(?:fail|missing|invariant|unreachable|timeout|raised|did not run|unset|error|broken|exited|forbidden)\b/i.freeze

      def forward(line, io: $stdout)
        text = line.to_s.scrub.gsub(ANSI, "").delete("\r").chomp
        return if text.strip.empty?

        terminal_write(io:) do |target|
          target.puts(text)
          target.flush if target.respond_to?(:flush)
        end
        if NARRATED_FORWARD_LINE.match?(text) || NARRATED_FORWARD_FINDING.match?(text)
          narrate(text)
          speak_log_line(text) if log_voice_active?
        end
        text
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.forward")
        nil
      end

      # The story is the default voice for what the runtime prints; the Narrator picks its teller,
      # the bard or the factual voice, which decides what is worth telling and when.
      def narrate(text)
        defined?(Master::Voice::Narrator) && Master::Voice::Narrator.observe(text)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.narrate")
      end

      # With narration on, a printed line is an event for the story and is not
      # also read out on its own; MASTER_NARRATE=0 restores the one-line style.
      def narration_owns_voice?
        defined?(Master::Voice::Narrator) && Master::Voice::Narrator.narrating?
      end

      def speak_log_line(text)
        return if Thread.current[:master_dmesg_tts]
        return if narration_owns_voice?

        return if text.match?(/\A(?:voice|tts)\d+(?: at [^:]+)?:/i)

        require_relative "../voice/playback"
        return unless Master::Voice::Playback.enabled?
        return unless Master::Voice::Playback.available?

        speech = Master::Voice::Speech
        clean = speech.clean_text(text)
        return if clean.empty?

        Thread.current[:master_dmesg_tts] = true
        accepted = Master::Voice::Playback.enqueue(
          clean,
          voice: Master::Voice::Policy.operator_log_voice,
          style: :neutral,
          rate: Master::Voice::Policy.operator_log_rate,
          pitch: Master::Voice::Policy.operator_log_pitch,
          last: true,
        )
        @recent_log_voice = [Process.clock_gettime(Process::CLOCK_MONOTONIC), clean] if accepted
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.log_voice")
      ensure
        Thread.current[:master_dmesg_tts] = false
      end

      def style(text, io: $stdout)
        text
      end

      ANSI = /\e\[[0-9;?]*[A-Za-z]/
      VERDICT = /\b(?:fail(?:ed|ures?)?|errors?|offen[cs]es?|violations?|exceed(?:s|ed)?|missing|expected|refused)\b/i
      FINDING = Regexp.union(/:\d+\b/, VERDICT)
      FINDING_LIMIT = 8

      def line(unit, parent, detail) = "#{unit} at #{parent}: #{detail}"

      # A bounded diff preview shared by whole-file writes and accepted repairs.
      # UnifiedDiff owns the comparison; this layer only removes temp-file headers.
      def diff_head(before, after, limit: 6)
        require_relative "../fix/unified_diff" unless defined?(Master::Fix::UnifiedDiff)
        diff = Master::Fix::UnifiedDiff.between(before, after, context: 0)
        return "diff unavailable" if diff.nil?

        diff.lines.reject do |line|
          line.start_with?("diff --git ", "index ", "--- ", "+++ ")
        end.first(Integer(limit)).join.rstrip
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.diff_head")
        "diff unavailable (#{e.class})"
      end

      def plain(text) = text.to_s.scrub.gsub(ANSI, "").delete("\r")

      def collapse(lines)
        lines.map(&:chomp).chunk_while { |a, b| a == b }.map do |run|
          run.size > 1 ? "#{run.first} x#{run.size}" : run.first
        end
      end

      def findings(text, limit: FINDING_LIMIT)
        lines = collapse(plain(text).lines).reject { |candidate| candidate.strip.empty? }
        hits = lines.grep(FINDING)
        picked = hits.empty? ? lines.last(limit) : hits.first(limit)
        picked.map { |finding| finding.strip[0, 200] }
      end

      def duration(seconds)
        return format("%.1fs", seconds) if seconds < 60

        minutes, rest = seconds.round.divmod(60)
        "#{minutes}m #{rest}s"
      end

      def counted(number, noun) = "#{number} #{noun}#{"s" unless number == 1}"

      def pastel
        nil
      end

      # A turn as the kernel would print it. Every model call, file, command
      # and request attaches as a numbered unit under its parent, the way sd1 is
      # the second disk, then reports once on what it did. A parent attaches
      # before its first child. An event with no unit renders nothing and stays
      # in the event log.
      class Console
        TOOL_UNITS = {
          "read_file" => %w[read io0], "list_dir" => %w[list io0], "search_files" => %w[grep io0],
          "search_knowledge" => %w[grep io0], "symbol_lookup" => %w[grep io0], "write_file" => %w[write io0],
          "str_replace" => %w[edit io0], "replace" => %w[edit io0], "ast_edit" => %w[edit io0],
          "zsh" => %w[exec io0], "git_context" => %w[git io0], "web_fetch" => %w[fetch net0],
          "web_search" => %w[search net0], "dynamic_http" => %w[http net0], "ask_llm" => %w[ask io0]
        }.freeze
        FOLD_UNITS = { "read" => "read", "write" => "write", "exec" => "exec", "git" => "git",
                       "ask" => "ask", "critique" => "crit" }.freeze
        PARENT_DETAIL = { "io0" => "files and commands", "net0" => "network", "fold0" => "coding loop" }.freeze
        DETAIL_CHARS = 96
        MS_PER_SECOND = 1000.0
        CENTS_PER_DOLLAR = 100

        def initialize
          @count = Hash.new(0)
          @open = {}
          @attached = {}
          @usage = nil
          @llm = {}
          @llm_parent = {}
          @ledger = Hash.new(0)
        end

        def lines(payload)
          track(payload)
          case payload[:event].to_s
          when "llm:send" then llm_send(payload)
          when "llm:call_complete" then remember_usage(payload)
          when "llm:provider_outcome" then llm_outcome(payload)
          when "tool:call" then tool_call(payload)
          when "tool:return" then tool_return(payload)
          when "fold:risk" then parent("fold0", "master0", "risk #{payload[:risk]}")
          when "core:reason" then reason_metadata(payload)
          when "core:turn" then fold_turn(payload)
          when "fix_loop:terminal" then terminal(payload)
          when "wishlist:done" then ["wish0: drafted #{payload[:drafted]} proposal(s)"]
          when "wishlist:error" then ["wish0: failed - #{clip(payload[:error])}"]
          else
            verbose_event(payload)
          end
        end

        private

        # Lanes ask in parallel, often of one model, so a call is its model on
        # its thread: the bus publishes in the caller's thread, and a call's
        # send and outcome happen on the same one. A call attaches to the unit
        # that asked for it, fold0 or scan0, named by Dmesg.under; anything else
        # asks from master0.
        #
        # A burst is not a conversation. A scan asks a model per file per rule,
        # and a line for each send and each outcome buried the operator: the
        # 2026-09-16 /fix printed some two thousand llm lines, every one of them
        # a lane failing over to the next, and no report at the end. The first
        # calls under a unit still attach, as devices do; past that the unit
        # speaks in rollups — how many were asked, how many failed, how many
        # lanes it walked — and a failure the chain recovered from is not news.
        # Every call is still in runtime/events/activity.jsonl.
        BURST_AFTER = 3
        ROLLUP_EVERY = 25
        ROLLUP_SECONDS = 20

        def llm_send(payload)
          parent = Fiber[:master_unit] || "master0"
          unit = open_unit("llm", llm_key(payload))
          Dmesg.bind_detail_unit("llm", unit)
          @llm_parent[llm_key(payload)] = parent
          tally = llm_tally(parent)
          tally[:calls] += 1
          tally[:models] << model_name(payload[:model])
          return ["#{unit} at #{parent}: #{model_name(payload[:model])}"] if Dmesg.detail_enabled? || Dmesg.verbose? || tally[:calls] <= BURST_AFTER

          rollup(parent, tally)
        end

        def llm_outcome(payload)
          key = llm_key(payload)
          unit = @open.delete(key) || "llm0"
          # The outcome is published on the thread that sent, so the unit that
          # asked is still in fiber storage when the send's key does not match.
          parent = @llm_parent.delete(key) || Fiber[:master_unit] || "master0"
          usage, @usage = @usage, nil
          tally = llm_tally(parent)
          tally[:failed] += 1 unless payload[:status].to_s == "success"
          return rollup(parent, tally) if !Dmesg.detail_enabled? && !Dmesg.verbose? && tally[:calls] > BURST_AFTER

          unless payload[:status].to_s == "success"
            digest = payload[:error_digest].to_s
            bytes = payload[:error_bytes]
            diagnostic = if !digest.empty?
              "diagnostic #{digest[0, 12]} (#{bytes} bytes)"
            elsif payload[:error]
              "diagnostic details redacted"
            end
            summary = [payload[:status], diagnostic].compact.join(", ")
            return ["#{unit}: #{summary}"]
          end

          ["#{unit}: #{[tokens(usage), seconds(payload[:latency_ms]), cents(usage)].compact.join(', ')}"]
        end

        def llm_tally(parent)
          @llm[parent] ||= { calls: 0, failed: 0, models: Set.new, said: 0, at: monotonic }
        end

        # One line per ROLLUP_SECONDS or ROLLUP_EVERY calls, whichever comes
        # first, and never one that repeats the last.
        def rollup(parent, tally)
          since = tally[:calls] - tally[:said]
          return [] if since < ROLLUP_EVERY && monotonic - tally[:at] < ROLLUP_SECONDS
          return [] if since.zero?

          tally[:said] = tally[:calls]
          tally[:at] = monotonic
          failed = tally[:failed].positive? ? ", #{tally[:failed]} failed" : ""
          ["#{parent}: #{counted(tally[:calls], "model call")}#{failed}, #{counted(tally[:models].size, "lane")}"]
        end

        def track(payload)
          event = payload[:event].to_s
          event.start_with?("llm:") ? track_model(event, payload) : track_repair(event, payload)
        end

        def track_model(event, payload)
          case event
          when "llm:send"
            @ledger[:model_calls] += 1
          when "llm:provider_outcome"
            @ledger[:model_failures] += 1 unless payload[:status].to_s == "success"
          end
        end

        def track_repair(event, payload)
          case event
          when "fix_loop:pass_start"
            @ledger[:passes] = [@ledger[:passes].to_i, payload[:pass].to_i].max
            @ledger[:files] = [@ledger[:files].to_i, payload[:file_count].to_i].max
          when "fix_loop:scan_progress" then @ledger[:finding_files] += 1
          when "fix_loop:rule_result", "repair_loop:pass"
            @ledger[:rules] += 1
            @ledger[:violations] += payload[:violations].to_i
            @ledger[:fixed] += payload[:fixed].to_i
          when "repair_loop:fix_applied", "fix_loop:ast_fixed" then @ledger[:changes] += 1
          when "fix_loop:improvement_fix", "fix_loop:opportunity_fix", "fix_loop:visual_fix"
            @ledger[:model_fixes] += payload[:fixed].to_i
          when "fix_loop:improvement_council" then @ledger[:council] += 1
          when "fix_loop:human_decision_required" then @ledger[:human_decisions] += 1
          end
        end

        # Per-item churn: one line for each file a scan reads, passes or finishes,
        # each finding a hook sees, each cognition tick. A chat turn that set off
        # a background self-scan printed 2,657 of these ahead of a one-line
        # reply. Verbose shows the work; trace shows every item of it.
        CHURN = %w[scan:file_read scan:pass scan:complete scan:semantic_skipped scan:progress
                   hook:on_violation_found cognition:tick homeostat:observe conflict:resolved].freeze

        def verbose_event(payload)
          return [] unless Dmesg.verbose? || Dmesg.trace?

          event = payload[:event].to_s
          return [] if event.empty?
          return [] if CHURN.include?(event) && !Dmesg.trace?

          [event_line(payload)]
        end

        def event_line(payload)
          event = payload[:event].to_s
          component, action = event.split(":", 2)
          unit = DmesgUnit.unit_name(component)
          detail = event_detail(payload, action:)
          detail = trace_detail(payload) if Dmesg.trace?
          detail.empty? ? "#{unit}: #{action || "event"}" : "#{unit}: #{action || "event"}, #{detail}"
        end

        EVENT_FIELDS = %i[target path file pass file_count count rule status state fixed violations changes stage reason category ms bytes critiques files].freeze

        def trace_detail(payload)
          data = payload.reject { |key, _| %i[event ts].include?(key.to_sym) }
          rendered = Master::Ground::Redactor.payload(data).to_s
          clip(rendered, DETAIL_CHARS)
        rescue StandardError
          event_detail(payload)
        end

        def event_detail(payload, action: nil)
          values = EVENT_FIELDS.filter_map do |key|
            next if key.to_s == action.to_s
            value = payload[key]
            next if value.nil? || value == ""

            label = key.to_s.tr("_", " ")
            rendered = case value
                       when Array then value.first(3).map(&:to_s).join(", ")
                       else value.to_s
                       end
            next if rendered.empty?

            "#{label} #{clip(rendered, 72)}"
          end
          values.join(", ")
        end

        def terminal(payload)
          state = payload[:state].to_s
          message = clip(payload[:message], 80)
          lines = ["fix0: terminal #{state}"]
          lines[0] = "#{lines[0]}, #{message}" unless message.empty?
          return lines unless Dmesg.verbose? || Dmesg.trace?

          ledger = []
          ledger << counted(@ledger[:files].to_i, "file in scope") if @ledger[:files].to_i.positive?
          ledger << counted(@ledger[:rules].to_i, "rule pass") if @ledger[:rules].to_i.positive?
          ledger << counted(@ledger[:violations].to_i, "rule finding") if @ledger[:violations].to_i.positive?
          ledger << counted(@ledger[:fixed].to_i, "fix") if @ledger[:fixed].to_i.positive?
          ledger << counted(@ledger[:changes].to_i, "change") if @ledger[:changes].to_i.positive?
          ledger << counted(@ledger[:model_calls].to_i, "model call") if @ledger[:model_calls].to_i.positive?
          ledger << counted(@ledger[:model_failures].to_i, "model failure") if @ledger[:model_failures].to_i.positive?
          ledger << counted(@ledger[:council].to_i, "council review") if @ledger[:council].to_i.positive?
          ledger << counted(@ledger[:human_decisions].to_i, "human decision") if @ledger[:human_decisions].to_i.positive?
          lines << "fix0: ledger, #{ledger.join(", ")}" unless ledger.empty?
          @ledger = Hash.new(0)
          lines
        end

        def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Tokens and cost arrive inside the call; the outcome that closes the
        # unit arrives after it.
        def remember_usage(payload)
          @usage = payload
          []
        end

        # Shared event logs must not persist model-authored reason text. Accept
        # old event shapes only as a signal that a legacy payload was redacted.
        def reason_metadata(payload)
          digest = payload[:why_digest].to_s
          bytes = Integer(payload[:why_bytes])
          return ["fold0: reason received (#{bytes} bytes, sha256 #{digest[0, 12]})"] if digest.match?(/\A[0-9a-f]{64}\z/) && bytes >= 0

          ["fold0: reason received (legacy payload redacted)"]
        rescue ArgumentError, TypeError
          ["fold0: reason metadata unavailable"]
        end

        def public_subject(payload)
          kind = payload[:subject_kind].to_s
          bytes = payload[:subject_bytes]
          digest = payload[:subject_digest].to_s
          if !kind.empty? && bytes.to_s.match?(/\A\d+\z/)
            suffix = digest.match?(/\A[0-9a-f]{64}\z/) ? ", sha256 #{digest[0, 12]}" : ""
            return "#{kind} target (#{bytes} bytes#{suffix})"
          end

          legacy = payload[:subject].to_s
          legacy.empty? ? "target unavailable" : "target redacted (#{legacy.bytesize} bytes)"
        end

        def public_error(payload)
          digest = payload[:error_digest].to_s
          bytes = payload[:error_bytes]
          if digest.match?(/\A[0-9a-f]{64}\z/) && bytes.to_s.match?(/\A\d+\z/)
            return "failed (#{bytes} bytes, sha256 #{digest[0, 12]})"
          end

          payload.key?(:error) ? "failed (legacy diagnostic redacted)" : "failed"
        end

        def tool_call(payload)
          kind, parent_unit = TOOL_UNITS.fetch(payload[:tool].to_s, [payload[:tool].to_s, "io0"])
          unit = open_unit(kind, "tool:#{payload[:tool]}")
          Dmesg.bind_detail_unit(payload[:tool], unit)
          [*parent(parent_unit, "master0"), "#{unit} at #{parent_unit}: #{public_subject(payload)}"]
        end

        def tool_return(payload)
          unit = @open.delete("tool:#{payload[:tool]}")
          Dmesg.clear_detail_unit(payload[:tool])
          return [] unless unit
          return ["#{unit}: #{public_error(payload)}"] unless payload[:ok]

          ["#{unit}: #{[size(payload[:bytes]), seconds(payload[:ms])].compact.join(', ')}"]
        end

        def fold_turn(payload)
          verb = payload[:verb].to_s
          lines = parent("fold0", "master0")
          return lines << "fold0: done, #{counted(payload[:turn].to_i + 1, "turn")}" if verb == "done"
          return lines << "fold0: #{verb}, #{clip(payload[:subject])}" unless FOLD_UNITS.key?(verb)

          unit = next_unit(FOLD_UNITS[verb])
          lines << "#{unit} at fold0: #{clip(payload[:subject])}"
          lines << "#{unit}: #{fold_result(verb, payload)}"
        end

        def fold_result(verb, payload)
          return "failed" unless payload[:ok]

          detail = payload[:detail].to_s
          bytes = payload.fetch(:output_bytes, detail.bytesize)
          line_count = payload.fetch(:output_lines, detail.lines.size)
          return "#{size(bytes)}, #{counted(line_count, "line")}" if verb == "read"
          return "ok, #{counted(line_count, "line")}" if verb == "exec"

          clip(detail.lines.first || "ok")
        end

        def parent(unit, grandparent, detail = PARENT_DETAIL[unit])
          return [] if @attached[unit]

          @attached[unit] = true
          ["#{unit} at #{grandparent}: #{detail}"]
        end

        def open_unit(kind, key)
          @open[key] = next_unit(kind)
        end

        def next_unit(kind)
          number = @count[kind]
          @count[kind] += 1
          "#{kind}#{number}"
        end

        def llm_key(payload) = "llm:#{Thread.current.object_id}:#{payload[:model]}"

        def model_name(model) = model.to_s.delete_suffix(":free")

        def tokens(usage)
          return unless usage

          return "#{usage[:tokens_out].to_i} tokens out" if usage[:tokens_in].to_i.zero?

          "#{usage[:tokens_in].to_i} tokens in, #{usage[:tokens_out].to_i} out"
        end

        def cents(usage)
          cost = usage && usage[:cost_usd].to_f
          cost&.positive? ? format("%.2f cents", cost * CENTS_PER_DOLLAR) : nil
        end

        def seconds(ms) = ms ? format("%.1fs", ms.to_f / MS_PER_SECOND) : nil

        def size(bytes) = bytes ? counted(bytes.to_i, "byte") : nil

        def counted(number, noun) = Dmesg.counted(number, noun)

        def clip(text, limit = DETAIL_CHARS)
          flat = text.to_s.gsub(/\s+/, " ").strip
          Master::Voice::Typography.ellipsis(flat, limit)
        end
      end
    end
  end
end
