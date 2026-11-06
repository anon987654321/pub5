# frozen_string_literal: true

require "json"
require_relative "terminal"
require_relative "../models/dispatch"
require_relative "../memory/memory"
require_relative "../cognition/mind"

module Cli
  # One conversation: its turns, what memory adds to each prompt, and what
  # the mind learns from each turn's ledger entries. The REPL owns the
  # terminal; this owns the turn, so a face or web adapter would call the same
  # turn rather than a second router (UX025).
  #
  # The turns are saved after every answer (log/master/session.json), so a
  # REPL that is closed and opened again resumes where it was; /new starts
  # fresh. Moved from pub4 lib/cli/session.rb (its save!/resume) and the
  # turn half of session/repl_flow.rb.
  class Conversation
    PATH = "log/master/session.json"
    SCHEMA = 1
    MAX_TURNS = 20
    SYSTEM = "You are MASTER, the operator's terminal assistant for the pub5 repository. " \
             "Lead with the answer or the result, tersely, in plain text. No greetings, no filler, " \
             "no claims of having run or changed anything you did not."

    attr_reader :turns, :dispatch, :memory, :mind

    def initialize(world:, dispatch:, memory: nil, mind: nil)
      @world = world
      @dispatch = dispatch
      @memory = memory
      @mind = mind
      @turns = load
    end

    def resumed? = !@turns.empty?

    # The reply, or an exception the caller reports (Dispatch::Exhausted,
    # Core::Refusal, Interrupt). Either way the mind sees the turn.
    def turn(text)
      task_id = "t#{@turns.size + 1}"
      mark = @world.ledger.entries.size
      reply = @dispatch.ask(text, system: system_for(text), messages: messages)
      @turns << { "user" => text, "assistant" => reply.text, "model" => reply.model }
      @turns = @turns.last(MAX_TURNS)
      save
      @memory&.auto_save(text)
      observe(mark, task_id, ok: true)
      reply
    rescue StandardError, Interrupt
      observe(mark, task_id, ok: false) if mark
      raise
    end

    def reset!
      @turns = []
      save
    end

    def close = @mind&.tick!

    private

    def system_for(text)
      [SYSTEM, @memory&.context_summary, @memory&.turn_recall(text)].compact.join("\n\n")
    end

    def messages
      @turns.flat_map { |t| [{ role: "user", content: t["user"] }, { role: "assistant", content: t["assistant"] }] }
    end

    def observe(mark, task_id, ok:)
      return unless @mind

      @mind.observe_ledger(@world.ledger.entries.drop(mark), task_id:)
      @mind.observe(event: ok ? "turn:answered" : "turn:failed", payload: { task_id:, ok: })
    end

    def load
      data = JSON.parse(@world.read(PATH))
      data["schema"] == SCHEMA ? Array(data["turns"]) : []
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save = @world.write(PATH, "#{JSON.generate('schema' => SCHEMA, 'turns' => @turns)}\n", mode: 0o600)
  end
end
