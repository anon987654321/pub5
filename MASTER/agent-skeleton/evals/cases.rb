# frozen_string_literal: true

# Canned eval cases. Extend this file as MASTER grows; keep every case
# deterministic (offline) unless it is explicitly a live case.
#
# Requires lib/master (LLMAdapter, tools, subagents...) to be loaded first —
# bin/master-evals does that.

module Master
  module Evals
    def self.cases
      [
        Case.new("tool call then final answer") do |ctx|
          echo = EchoTool.new
          ctx.run_offline(
            script: [tool_call("echo", { "text" => "hello" }), final("final answer")],
            tools: [echo],
            task: "say hello"
          )
          ctx.assert(ctx.answer == "final answer", "final answer returned verbatim")
          ctx.assert(echo.received == ["hello"], "tool received correct args")
          history = ctx.memory.history("eval")
          ctx.assert(history.size == 2, "memory keeps user + assistant turns (got #{history.size})")
        end,

        Case.new("tool error is fed back, loop survives") do |ctx|
          ctx.run_offline(
            script: [tool_call("echo", {}), final("I handled the error")],
            tools: [EchoTool.new],
            task: "say hello (but forget the args)"
          )
          ctx.assert(ctx.answer == "I handled the error", "agent finished after tool error")
          roles = ctx.llm.calls[1][:roles]
          ctx.assert(roles.include?("tool"), "second LLM call saw the tool result message")
        end,

        Case.new("unknown tool does not crash the loop") do |ctx|
          ctx.run_offline(
            script: [tool_call("does_not_exist", {}), final("ok, moving on")],
            tools: [EchoTool.new],
            task: "call a tool that does not exist"
          )
          ctx.assert(ctx.answer == "ok, moving on", "agent finished despite unknown tool")
        end,

        Case.new("max steps guard stops runaway loops") do |ctx|
          script = Array.new(10) { |i| tool_call("echo", { "text" => "x#{i}" }, id: "call_#{i}") }
          ctx.run_offline(
            script: script,
            tools: [EchoTool.new],
            task: "loop forever",
            max_steps: 3
          )
          ctx.assert(ctx.max_steps_exceeded?, "MaxStepsExceeded raised")
          ctx.assert(ctx.memory.history("eval").size == 1,
                     "no assistant final turn persisted (got #{ctx.memory.history('eval').size})")
        end,

        Case.new("sub-agent fan-out is aligned and scoped") do |ctx|
          reg = Master::ToolRegistry.new.register(EchoTool.new)
          mem = Master::Memory.new(path: ctx.temp_db)
          subs = Master::Subagents.new(llm: TaskEchoLLM.new, tools: reg, memory: mem)
          dispatch = Master::Tools::DispatchSubtasks.new(subs)
          results = dispatch.call({ "tasks" => ["a", "b", "c"] })
          ctx.assert(results.is_a?(Array) && results.size == 3, "three aligned results")
          ctx.assert(results[1][:answer] == "done: b", "results align with input order")
          ctx.assert(subs.build_registry(nil)["dispatch_subtasks"].nil?,
                     "sub-agents cannot dispatch further subtasks")
          ctx.assert(subs.build_registry(["echo"])["echo"] &&
                     subs.build_registry(["echo"])["shell"].nil?,
                     "explicit tool scope is respected")
        end,

        Case.new("schedule_create persists an entry") do |ctx|
          store = Master::ScheduleStore.new(path: ctx.temp_db)
          ctx.run_offline(
            script: [tool_call("schedule_create",
                               { "name" => "s1", "schedule" => "every:1h", "prompt" => "hi" }),
                     final("scheduled s1")],
            tools: [Master::Tools::ScheduleCreate.new(store)],
            task: "create an hourly schedule"
          )
          ctx.assert(ctx.answer == "scheduled s1", "final answer returned")
          ctx.assert(store.list.size == 1, "schedule store has one entry")
          ctx.assert(store.list.first[:schedule] == "every:1h", "schedule string stored")
        end
      ]
    end

    def self.live_cases(llm)
      [
        Case.new("live: web_fetch round trip", mode: :live) do |ctx|
          ctx.run_live(
            llm: llm,
            tools: [Master::Tools::WebFetch.new],
            task: "Use the web_fetch tool on https://example.com and reply with only the page's title."
          )
          ctx.assert(!ctx.answer.to_s.empty?, "got a final answer")
          calls = ctx.chat_calls
          ctx.assert(calls.is_a?(Integer) && calls.between?(1, 8),
                     "sane number of LLM calls (got #{calls.inspect})")
          ctx.assert(ctx.answer.to_s.downcase.include?("example"),
                     "answer mentions the page title (got: #{ctx.answer.to_s[0, 80].inspect})")
        end
      ]
    end
  end
end
