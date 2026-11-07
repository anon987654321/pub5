# frozen_string_literal: true

require "did_you_mean"
require "etc"
require_relative "conversation"
require_relative "prompt"

module Cli
  # The REPL: `bin/master` on a terminal, or `bin/master repl`. Reads a line,
  # answers it, reports in dmesg lines, keeps the prompt. In a pipe it reads
  # one turn per line with no prompt, no line editor and no control sequences.
  #
  # Moved from pub4 lib/cli/session.rb, session/repl_flow.rb and
  # session/repl_io.rb, without the face overlay, voice, the background scan,
  # the threaded turn queue and the shell escape: lines typed during a turn
  # wait in the terminal's buffer and run in order after it.
  #
  #   empty or whitespace line  nothing happens
  #   /command [args]           a REPL command (/help lists them)
  #   <<                        multiline: lines until a blank one, sent as one
  #   anything else             one turn to the model
  #   ^C at the prompt          clears the line; a second within 3s quits
  #   ^C during a turn          cancels that turn; the prompt comes back
  #   ^D on an empty line       quits; a line with text is never discarded
  #
  # Exit status: 0, or 1 when any turn or command in the session failed.
  class Repl
    CLOSE_WINDOW_S = 3
    MULTILINE_MAX = 500
    HISTORY = "log/master/history"
    HISTORY_LIMIT = 1_000
    # The one table of REPL commands: help and completion both read it.
    COMMANDS = {
      "/help" => "list these commands",
      "/model" => "the pinned model, or the route and chain the next turn would use",
      "/lanes" => "lanes that are not answering, and until when",
      "/spend" => "model calls, tokens and cost in the ledger",
      "/memory" => "what memory holds, or /memory WORDS to search it",
      "/remember" => "/remember KEY TEXT saves a fact",
      "/forget" => "/forget KEY removes it and its history",
      "/mind" => "the cognition metrics and the last reflection",
      "/new" => "start a fresh session (the current one is not resumed)",
      "/quit" => "save and leave"
    }.freeze
    ALIASES = { "/exit" => "/quit", "/q" => "/quit", "/?" => "/help" }.freeze
    # Reline asks the terminal where the cursor is, and a late reply lands in
    # the input as text ("[38;51R") that would be saved as the operator's words.
    TERMINAL_REPLY = /\e?\[?\d{1,4};\d{1,4}R|\e\[[\d;?]*[A-Za-z~]/

    def initialize(world:, context:, input: $stdin, out: $stdout, err: $stderr, conversation: nil, clock: nil)
      @world = world
      @context = context
      @input = input
      @out = out
      @err = err
      @conversation = conversation
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @tty = context == "tty"
      @exit_code = 0
    end

    def call(argv)
      return usage("repl takes no arguments; to ask once, bin/master ask \"...\"") unless argv.empty?

      setup_line_editor if @tty
      @tty ? boot_dmesg : boot_line
      loop do
        line = read_line
        break if line.nil?

        handle(line) unless line == :interrupted
        break if @quit
      end
      @exit_code
    ensure
      close
    end

    def handle(line)
      text = line.to_s.strip
      return if text.empty?
      return handle_multiline if text == "<<"
      return command(text) if text.start_with?("/")

      ask(text)
    end

    private

    def conversation
      @conversation ||= begin
        knobs = Core::Knobs.default
        memory = Memory::Store.new(world: @world)
        Conversation.new(world: @world, memory:,
                         mind: Cognition::Mind.new(store: Cognition::Mind::Store.new(@world), memory:),
                         dispatch: Models::Dispatch.build(@world, knobs:, say: ->(l) { status_raw(l) }))
      end
    end

    # One line, no banner: where this is, how the next turn routes, what is
    # down. A pipe gets exactly this; a terminal gets the dmesg boot (boot_dmesg).
    def boot_line
      c = conversation
      status("repl", "#{File.basename(@world.manifest.root)} #{session_word(c)}; next turn #{route_of(c)}; #{down_lanes(c)} lanes down; /help")
    end

    # The boot is the kernel's (operator directive 2026-11-06: MASTER
    # resembles OpenBSD): the console prints its dmesg white on blue, the
    # splash is the last of the boot and keeps the colours, and the prompt
    # and the session's first status print plain. Ported from pub4
    # cli/session.rb#print_splash and Renderer#compact_splash, with this
    # tree's real units: the boot, the host, the root device, then the
    # session status a pipe reads as boot_line.
    def boot_dmesg
      c = conversation
      splash = [
        "master0 at mainbus0: pub5, model #{route_of(c)}",
        "host0 at mainbus0: #{Etc.getlogin || "master"}@#{Socket.gethostname}:#{@world.manifest.root}",
        "root on master0",
      ]
      @err.puts(Terminal.boot_splash(splash, io: @err,
                                     colorterm: @world.knobs.fetch("COLORTERM"),
                                     no_color: @world.knobs.fetch("NO_COLOR")))
      @err.puts
      status("repl", "#{session_word(c)}; #{down_lanes(c)} lanes down; /help")
    end

    def route_of(c)
      c.dispatch.router.pin || c.dispatch.router.chain("exploration").first || "no lane"
    end

    def session_word(c)
      c.resumed? ? "resumed #{c.turns.size} turns (/new starts fresh)" : "new session"
    end

    def down_lanes(c) = c.dispatch.lanes.report.size

    def ask(text)
      model = conversation.dispatch.router.pin || conversation.dispatch.router.chain(conversation.dispatch.router.classify(text)).first
      status("turn", "asking #{model || 'no lane'}; ^C cancels") if @tty
      started = @clock.call
      reply = conversation.turn(text)
      @out.puts(Terminal.clean(reply.text))
      status("turn", "answered by #{reply.model} in #{(@clock.call - started).round(1)}s, #{Terminal.spend(reply)}")
    rescue Models::Dispatch::Exhausted => e
      fail_turn("FAILED no lane answered: #{e.message}; next: /lanes, or pin one with PUB5_MODEL")
    rescue Core::Refusal => e
      fail_turn("REFUSED #{e.message}")
    rescue Interrupt
      fail_turn("cancelled after #{(@clock.call - started).round(1)}s; nothing was saved")
    end

    def fail_turn(message)
      status("turn", message)
      @exit_code = 1
    end

    def command(text)
      name, rest = text.split(/\s+/, 2)
      name = ALIASES.fetch(name.downcase, name.downcase)
      unless COMMANDS.key?(name)
        near = DidYouMean::SpellChecker.new(dictionary: COMMANDS.keys + ALIASES.keys).correct(name).first
        return fail_command("unknown command #{name}#{near ? "; did you mean #{ALIASES.fetch(near, near)}?" : ''} (/help lists them)")
      end

      send(:"cmd_#{name.delete_prefix('/')}", rest.to_s.strip)
    rescue StandardError => e
      fail_command("#{name} failed - #{e.class}: #{e.message}")
    end

    def fail_command(message)
      status("cmd", message)
      @exit_code = 1
    end

    def cmd_help(_)
      width = COMMANDS.keys.map(&:size).max
      @out.puts(COMMANDS.map { |name, summary| "#{name.ljust(width)}  #{summary}" })
      @out.puts("<<#{' ' * (width - 2)}  multiline: lines until a blank one, sent as one turn")
      @out.puts("Anything else is a prompt to the model. There is no shell escape; MASTER commands start with /.")
      @out.puts("Examples: /remember deadline Friday   /memory relayd headers   /model")
    end

    def cmd_model(_)
      router = conversation.dispatch.router
      return @out.puts("pinned #{router.pin} (PUB5_MODEL); the only lane") if router.pin

      @out.puts("routed: exploration -> #{router.chain('exploration').first(4).join(', ')}")
      @out.puts("        code -> #{router.chain('code').first(4).join(', ')}")
    end

    def cmd_lanes(_)
      report = conversation.dispatch.lanes.report
      @out.puts(report.empty? ? "every lane may be asked" : report)
    end

    def cmd_spend(_)
      s = @world.ledger.spend
      @out.puts(format("%<calls>d calls, %<in>d in %<out>d out, $%<cost>.4f, %<unpriced>d unpriced",
                       calls: s["calls"], in: s["tokens_in"], out: s["tokens_out"], cost: s["cost_usd"],
                       unpriced: s["unpriced_calls"]))
    end

    def cmd_memory(query)
      memory = conversation.memory
      if query.empty?
        counts = memory.type_counts
        return @out.puts(counts.empty? ? "memory is empty" : counts.map { |t, n| "#{t} #{n}" }.join(", "))
      end

      hits = memory.keyword_recall(query, top_n: 5)
      @out.puts(hits.empty? ? "nothing in memory matches" : hits.map { |h| "#{h[:key]}: #{Terminal.clean(h[:value])}" })
    end

    def cmd_remember(rest)
      key, value = rest.split(/\s+/, 2)
      return fail_command("usage: /remember KEY TEXT") if value.to_s.empty?

      @out.puts("remembered #{conversation.memory.remember(key, value, source: 'operator:repl', confidence: 0.9)}")
    end

    def cmd_forget(key)
      return fail_command("usage: /forget KEY") if key.empty?

      conversation.memory.forget(key)
      @out.puts("forgot #{key}")
    end

    def cmd_mind(_)
      snapshot = conversation.mind.snapshot
      metrics = snapshot["metrics"].map { |k, v| "#{k} #{v.to_f.round(3)}" }.join(", ")
      @out.puts(metrics)
      thought = snapshot["thoughts"].first
      @out.puts(thought["text"]) if thought
    end

    def cmd_new(_)
      conversation.reset!
      @out.puts("new session")
    end

    def cmd_quit(_) = @quit = true

    def handle_multiline
      status("input", "multiline: enter lines, a blank line sends") if @tty
      lines = []
      while lines.size < MULTILINE_MAX && (line = read_line(@tty ? "  " : "")).is_a?(String) && !line.strip.empty?
        lines << line
      end
      ask(lines.join("\n")) unless lines.empty?
    end

    def read_line(prompt = prompt_text)
      return @input.gets&.chomp unless @tty

      line = Reline.readline(prompt, false)
      return if line.nil?

      line = [line, *pasted_lines].join("\n").gsub(TERMINAL_REPLY, "")
      Reline::HISTORY << line unless line.strip.empty? || Terminal.redact(line) != line
      line
    rescue Interrupt
      @out.puts
      return nil if close_requested?

      status("input", "^C again within #{CLOSE_WINDOW_S}s quits")
      :interrupted
    end

    # A paste the terminal did not bracket arrives as lines already waiting;
    # they join the first and stay one draft, never one turn each.
    def pasted_lines
      lines = []
      lines << Reline.readline("", false).to_s while lines.size < MULTILINE_MAX && Reline::IOGate.in_pasting?
      lines
    end

    def close_requested?
      now = @clock.call
      recent = @interrupted_at && now - @interrupted_at <= CLOSE_WINDOW_S
      @interrupted_at = now
      recent
    end

    # The OpenBSD operator prompt, vm23:~/pub5$, the repository it acts on
    # (pub4 lib/face.rb shell_prompt). Plain: the splash owns the colour.
    def prompt_text = "#{Prompt.shell_prompt(path: @world.manifest.root, host: Socket.gethostname)} "

    def setup_line_editor
      require "reline"
      Reline.completion_proc = ->(target) { (COMMANDS.keys + ["<<"]).select { |c| c.start_with?(target) } }
      text = @world.read(HISTORY)
      text.force_encoding(Encoding::UTF_8).scrub.lines(chomp: true).last(HISTORY_LIMIT).each { |l| Reline::HISTORY << l }
    rescue Errno::ENOENT
      nil
    end

    def close
      return if @closed

      @closed = true
      @conversation&.close
      return unless @tty && defined?(Reline)

      @world.write(HISTORY, "#{Reline::HISTORY.to_a.last(HISTORY_LIMIT).join("\n")}\n", mode: 0o600)
    end

    def status(unit, message) = @err.puts(Terminal.line(unit, message, width: Terminal.width(@err)))

    def status_raw(line) = @err.puts(Terminal.clean(line))

    def usage(problem)
      status("repl", "usage error: #{problem}")
      64
    end
  end
end
