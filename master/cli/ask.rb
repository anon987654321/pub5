# frozen_string_literal: true

require "json"
require_relative "terminal"
require_relative "../models/dispatch"

module Cli
  # `bin/master ask "..."`: one question, one answer, no session. The prompt
  # is the arguments, or stdin when there are none (`echo hi | bin/master
  # ask`). Boots core plus the model layer only.
  #
  # stdout carries the answer and nothing else; every status line goes to
  # stderr, outcome first. --json puts one versioned object on stdout
  # instead; -q drops the routine status line, never a failure.
  #
  # Exit status: 0 answered, 1 no lane answered, 64 usage, 70 refused
  # (offline, budget, an undeclared capability).
  class Ask
    USAGE = 'usage: bin/master ask [-q] [--json] "question"   (or the question on stdin)'
    JSON_SCHEMA = 1

    def initialize(world:, context:, input: $stdin, out: $stdout, err: $stderr, dispatch: nil)
      @world = world
      @context = context
      @input = input
      @out = out
      @err = err
      @dispatch = dispatch
    end

    def call(argv)
      argv = argv.dup
      quiet = argv.delete("-q") || argv.delete("--quiet")
      json = argv.delete("--json")
      unknown = argv.select { |a| a.start_with?("-") && a != "-" }
      return usage("unknown flag #{unknown.first}") if unknown.any?

      prompt = argv.empty? || argv == ["-"] ? read_stdin : argv.join(" ")
      return usage("empty question") if prompt.to_s.strip.empty?

      reply = dispatch.ask(prompt.strip)
      json ? @out.puts(JSON.generate(json_reply(reply))) : @out.puts(Terminal.clean(reply.text))
      say("answered by #{reply.model} in #{reply.seconds}s, #{Terminal.spend(reply)}") unless quiet
      0
    rescue Models::Dispatch::Exhausted => e
      say("FAILED no lane answered: #{e.message}; next: bin/master lanes, or pin one with PUB5_MODEL")
      1
    rescue Core::Refusal => e
      say("REFUSED #{e.message}")
      70
    end

    private

    def dispatch = @dispatch ||= Models::Dispatch.build(@world, knobs: Core::Knobs.default, say: ->(l) { @err.puts(Terminal.clean(l)) })

    def read_stdin = @input.tty? ? nil : @input.read

    def json_reply(reply)
      { "schema" => JSON_SCHEMA, "model" => reply.model, "text" => Terminal.redact(reply.text),
        "tokens_in" => reply.tokens_in, "tokens_out" => reply.tokens_out, "cost_usd" => reply.cost_usd,
        "seconds" => reply.seconds }
    end

    def say(message) = @err.puts(Terminal.line("ask", message))

    def usage(problem)
      @err.puts(Terminal.line("ask", "usage error: #{problem}"))
      @err.puts(USAGE)
      64
    end
  end
end

module Cli
  # `bin/master lanes`: the lanes that are not answering and until when; exit
  # 0 when every lane may be asked, 1 when some are down.
  class Lanes
    def initialize(world:, context:, out: $stdout)
      @world = world
      @out = out
    end

    def call(_argv)
      report = Models::Lanes.new(catalog: Models::Catalog.new, store: Models::Lanes::Store.new(@world)).report
      @out.puts(report.empty? ? "lanes0: every lane may be asked" : report.map { |l| Terminal.line("lanes", l) })
      report.empty? ? 0 : 1
    end
  end
end
