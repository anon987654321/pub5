# frozen_string_literal: true

require "json"
require_relative "terminal"
require_relative "../models/dispatch"
require_relative "../memory/memory"
require_relative "../cognition/mind"
require_relative "../tools/research"

module Cli
  # One conversation: its turns, what memory adds to each prompt, and what
  # the mind learns from each turn's ledger entries. The REPL owns the
  # terminal; this owns the turn, so a face or web adapter would call the
  # same turn rather than a second router.
  #
  # Tool calls use a bounded, model-neutral JSON envelope. The same loop works
  # for text-only subscription CLIs and HTTP models; actual effects still pass
  # through Core::World and the invoking command's capability manifest.
  class Conversation
    PATH = "log/master/session.json"
    SCHEMA = 1
    MAX_TURNS = 20
    MAX_TOOL_CALLS = 6
    SYSTEM = "You are MASTER, the operator's terminal assistant for the pub5 repository. " \
             "Lead with the answer or the result, tersely, in plain text. No greetings, no filler, " \
             "no claims of having run or changed anything you did not."

    attr_reader :turns, :dispatch, :memory, :mind

    def initialize(world:, dispatch:, memory: nil, mind: nil, research: nil)
      @world = world
      @dispatch = dispatch
      @memory = memory
      @mind = mind
      @research = research || Master::Tools::Research.new(world:)
      @turns = load
    end

    def resumed? = !@turns.empty?

    # The reply, or an exception the caller reports (Dispatch::Exhausted,
    # Core::Refusal, Interrupt). Either way the mind sees the turn.
    def turn(text)
      task_id = "t#{@turns.size + 1}"
      mark = @world.ledger.entries.size
      reply = turn_with_tools(text)
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

    def close
      @research.close if @research.respond_to?(:close)
      @mind&.tick!
    end

    private

    def turn_with_tools(text)
      base_system = system_for(text)
      tools = @research.available_tools
      protocol = tools.empty? ? @research.permission_note : @research.tool_prompt
      system = [base_system, protocol].compact.reject(&:empty?).join("\n\n")
      history = messages
      prompt = text
      reply = @dispatch.ask(prompt, system:, messages: history)
      history = [*history, { role: "user", content: prompt }, { role: "assistant", content: reply.text }]

      seen = {}
      calls = 0
      loop do
        call = @research.parse_tool_call(reply.text)
        break unless call

        if calls >= MAX_TOOL_CALLS
          final_prompt = "The research tool-call budget is exhausted. Do not call another tool. " \
                         "Give the best answer supported by the evidence already gathered, and name any remaining uncertainty."
          reply = @dispatch.ask(final_prompt, system:, messages: history)
          break
        end

        fingerprint = JSON.generate(call)
        result = if seen[fingerprint]
                   "Refused a duplicate tool call. Use different arguments or answer from the evidence already gathered."
                 else
                   seen[fingerprint] = true
                   @research.call(name: call.fetch("name"), arguments: call.fetch("arguments"))
                 end
        prompt = @research.result_prompt(name: call.fetch("name"), result:)
        reply = @dispatch.ask(prompt, system:, messages: history)
        history = [*history, { role: "user", content: prompt }, { role: "assistant", content: reply.text }]
        calls += 1
      end
      reply
    end

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
