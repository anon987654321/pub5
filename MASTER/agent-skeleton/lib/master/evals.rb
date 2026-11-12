# frozen_string_literal: true

require "json"
require "tempfile"
require_relative "tool_registry"
require_relative "agent"
require_relative "memory"

module Master
  module Evals
    class EvalError < StandardError; end

    # ------------------------------------------------------------------
    # Test doubles
    # ------------------------------------------------------------------

    # Scripted LLM: pops canned assistant messages, records what it saw.
    class FakeLLM
      attr_reader :calls

      def initialize(script)
        @script = script.dup
        @calls = []
      end

      def chat(messages, tools: [])
        @calls << {
          roles: messages.map { |m| (m.is_a?(Hash) ? (m["role"] || m[:role]) : "?").to_s },
          tool_schemas: tools.size
        }
        @script.shift || raise(EvalError, "FakeLLM script exhausted")
      end
    end

    # Stateless LLM that answers "done: <task>" — for sub-agent fan-out.
    class TaskEchoLLM
      attr_reader :calls

      def initialize
        @calls = 0
      end

      def chat(messages, _tools: [])
        @calls += 1
        last = messages.last || {}
        task = (last["content"] || last[:content] || "").to_s
        { "role" => "assistant", "content" => "done: #{task}" }
      end
    end

    # Wraps a real LLMAdapter to count chat calls in live runs.
    class CountingLLM
      attr_reader :calls

      def initialize(inner)
        @inner = inner
        @calls = 0
      end

      def chat(messages, tools: [])
        @calls += 1
        @inner.chat(messages, tools: tools)
      end
    end

    # Tool that records what it was asked to do.
    class EchoTool < Master::Tool
      attr_reader :received

      def initialize
        @received = []
      end

      def name
        "echo"
      end

      def description
        "echoes text"
      end

      def parameters
        { type: "object", properties: { text: { type: "string" } }, required: ["text"] }
      end

      def call(args)
        text = args.fetch("text")
        @received << text
        { said: text }
      end
    end

    # Canned-message builders for scripts.
    def self.tool_call(name, args, id: "call_1")
      { "role" => "assistant", "content" => nil, "tool_calls" => [{
        "id" => id, "type" => "function",
        "function" => { "name" => name, "arguments" => JSON.generate(args) }
      }] }
    end

    def self.final(text)
      { "role" => "assistant", "content" => text }
    end

    # ------------------------------------------------------------------
    # Case context: helpers a case block can use.
    # ------------------------------------------------------------------

    class Context
      attr_reader :failures, :answer, :agent, :memory, :registry, :llm

      def initialize
        @failures = []
        @tempfiles = []
        @answer = nil
      end

      def assert(ok, message)
        @failures << message unless ok
        ok
      end

      def temp_db
        f = Tempfile.new(["master_eval", ".db"])
        @tempfiles << f
        f.path
      end

      def cleanup
        @tempfiles.each { |f| f.unlink rescue nil }
      end

      def chat_calls
        @llm.respond_to?(:calls) ? @llm.calls : nil
      end

      def max_steps_exceeded?
        @max_steps_exceeded == true
      end

      # Offline run: scripted LLM, real agent loop, real tools.
      def run_offline(script:, tools:, task:, max_steps: 10, thread: "eval")
        @llm = FakeLLM.new(script)
        @registry = Master::ToolRegistry.new
        tools.each { |t| @registry.register(t) }
        @memory = Master::Memory.new(path: temp_db)
        @agent = Master::Agent.new(llm: @llm, tools: @registry, memory: @memory, max_steps: max_steps)
        @answer = @agent.run(task, thread_id: thread)
        self
      rescue Master::MaxStepsExceeded
        @max_steps_exceeded = true
        self
      end

      # Live run: real LLM backend, real agent loop, real tools.
      def run_live(llm:, tools:, task:, max_steps: 8, thread: "eval-live")
        @llm = llm
        @registry = Master::ToolRegistry.new
        tools.each { |t| @registry.register(t) }
        @memory = Master::Memory.new(path: temp_db)
        @agent = Master::Agent.new(llm: @llm, tools: @registry, memory: @memory, max_steps: max_steps)
        @answer = @agent.run(task, thread_id: thread)
        self
      end
    end

    # ------------------------------------------------------------------
    # Case + Runner
    # ------------------------------------------------------------------

    class Case
      attr_reader :name, :mode

      def initialize(name, mode: :offline, &block)
        @name = name
        @mode = mode
        @block = block
      end

      def run
        ctx = Context.new
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          @block.call(ctx)
        rescue StandardError => e
          ctx.failures << "raised #{e.class}: #{e.message}"
        ensure
          ctx.cleanup
        end
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        { name: @name, mode: @mode.to_s, ok: ctx.failures.empty?,
          failures: ctx.failures, chat_calls: ctx.chat_calls, duration_ms: duration }
      end
    end

    class Runner
      def self.run(cases)
        cases.map(&:run)
      end

      def self.print_report(results)
        results.each do |r|
          status = r[:ok] ? "PASS" : "FAIL"
          detail = r[:failures].join("; ")
          puts format("%-4s %-48s %s", status, r[:name], detail)
        end
        passed = results.count { |r| r[:ok] }
        puts "-" * 60
        puts "#{passed}/#{results.size} passed"
      end

      def self.write_json(results, path)
        report = {
          generated_at: Time.now.utc.iso8601,
          totals: {
            total: results.size,
            passed: results.count { |r| r[:ok] },
            failed: results.count { |r| !r[:ok] }
          },
          cases: results
        }
        File.write(path, JSON.pretty_generate(report) + "\n")
        path
      end
    end
  end
end
