# frozen_string_literal: true

# Smoke test for the MASTER skeleton.
# Run from the repo root:  ruby test/smoke_test.rb
# Only needs the `sqlite3` gem (no network, no LLM, no scheduler runtime).

require "tempfile"
require_relative "../lib/master/tool_registry"
require_relative "../lib/master/agent"
require_relative "../lib/master/memory"
require_relative "../lib/master/vector_memory"
require_relative "../lib/master/schedule_store"
require_relative "../lib/master/subagents"
require_relative "../lib/master/tools/memory_tools"
require_relative "../lib/master/tools/schedule_tools"
require_relative "../lib/master/tools/dispatch"

# --- fixtures -----------------------------------------------------------

class FakeLLM
  def initialize(script)
    @script = script
  end

  def chat(_messages, tools: [])
    @script.shift or raise "FakeLLM script exhausted"
  end
end

class EchoTool < Master::Tool
  def name = "echo"
  def description = "echoes text"
  def parameters
    { type: "object", properties: { text: { type: "string" } }, required: ["text"] }
  end
  def call(args) = { said: args.fetch("text") }
end

# --- 1. registry: happy path, unknown tool, missing args ---------------

registry = Master::ToolRegistry.new.register(EchoTool.new)
r1 = registry.dispatch("echo", { "text" => "hi" })
abort "FAIL 1a" unless r1 == { said: "hi" }

r2 = registry.dispatch("nope", {})
abort "FAIL 1b" unless r2[:error].include?("unknown tool")

r3 = registry.dispatch("echo", {})
abort "FAIL 1c" unless r3[:error].include?("missing required")

abort "FAIL 1d" unless registry.schemas.first[:function][:name] == "echo"

# --- 2. agent loop: tool call, then final answer -----------------------

db = Tempfile.new("master_smoke")
memory = Master::Memory.new(path: db.path)
agent = Master::Agent.new(
  llm: FakeLLM.new([
    { "role" => "assistant", "content" => nil, "tool_calls" => [{
      "id" => "call_1", "type" => "function",
      "function" => { "name" => "echo", "arguments" => "{\"text\":\"hello\"}" }
    }] },
    { "role" => "assistant", "content" => "final answer" }
  ]),
  tools: registry,
  memory: memory
)
answer = agent.run("say hello", thread_id: "t1")
abort "FAIL 2a" unless answer == "final answer"
h = memory.history("t1")
abort "FAIL 2b (expected user+assistant rows, got #{h.size})" unless h.size == 2
abort "FAIL 2c" unless h.first["role"] == "user" && h.last["content"] == "final answer"

# --- 3. max steps guard -------------------------------------------------

always_call = FakeLLM.new(Array.new(20) do
  { "role" => "assistant", "content" => nil, "tool_calls" => [{
    "id" => "x", "type" => "function",
    "function" => { "name" => "echo", "arguments" => "{}" } }] }
end)
agent2 = Master::Agent.new(llm: always_call, tools: registry, memory: memory, max_steps: 3)
begin
  agent2.run("loop forever", thread_id: "t2")
  abort "FAIL 3a (expected MaxStepsExceeded)"
rescue Master::MaxStepsExceeded
  nil # expected
end

# --- 4. schedule store ----------------------------------------------------

store = Master::ScheduleStore.new(path: db.path)
store.create(name: "morning", schedule: "cron:0 9 * * *", prompt: "morning brief")
begin
  store.create(name: "morning", schedule: "every:1h", prompt: "dup")
  abort "FAIL 4a (expected duplicate name error)"
rescue Master::ScheduleError
  nil # expected
end
begin
  store.create(name: "bad", schedule: "daily", prompt: "x")
  abort "FAIL 4b (expected invalid schedule error)"
rescue Master::ScheduleError
  nil # expected
end
abort "FAIL 4c" unless store.list.size == 1
store.mark_run(store.list.first[:id], "done")
abort "FAIL 4d" unless store.list.first[:last_run_at]
store.delete("morning")
abort "FAIL 4e" unless store.list.empty?

# --- 5. sub-agents: single, parallel, scoping ------------------------------

class ProcLLM
  def chat(messages, _tools: [])
    task = messages.last["content"].to_s
    { "role" => "assistant", "content" => "done: #{task}" }
  end
end

subagents = Master::Subagents.new(llm: ProcLLM.new, tools: registry, memory: memory)
registry.register(Master::Tools::DispatchSubtasks.new(subagents))

single = subagents.run("do thing")
abort "FAIL 5a" unless single[:answer] == "done: do thing"

parallel = Master::Tools::DispatchSubtasks.new(subagents)
                                        .call({ "tasks" => ["task one", "task two"] })
abort "FAIL 5b" unless parallel.is_a?(Array) && parallel.size == 2
abort "FAIL 5c" unless parallel[0][:answer] == "done: task one"
abort "FAIL 5d" unless parallel[1][:answer] == "done: task two"

scoped = subagents.build_registry(nil) # default scope: all but dispatch
abort "FAIL 5e" unless scoped["echo"] && scoped["dispatch_subtasks"].nil?

narrow = subagents.build_registry(["echo"])
abort "FAIL 5f" unless narrow["echo"] && narrow["shell"].nil? && narrow["dispatch_subtasks"].nil?

# --- 6. vector memory + remember/recall tools ------------------------------

class FakeEmbedder
  LETTERS = "abcdef".chars

  def embed(text)
    t = text.to_s.downcase
    LETTERS.map { |c| t.count(c).to_f }
  end
end

vectors = Master::VectorMemory.new(path: db.path, embedder: FakeEmbedder.new)
vectors.add("abc abc", thread_id: "v")
vectors.add("def def", thread_id: "v")
top = vectors.search("abc", k: 2).first
abort "FAIL 6a" unless top[:text] == "abc abc"
begin
  vectors.add("zzz", thread_id: "v") # FakeEmbedder always returns dim 6; fine
rescue Master::VectorMemoryError
  abort "FAIL 6b (unexpected dimension mismatch)"
end

Master::Tools::Remember.new(vectors).call({ "text" => "abcdef" })
recalled = Master::Tools::Recall.new(vectors).call({ "query" => "abc", "k" => 3 })
abort "FAIL 6c" unless recalled[:notes].first[:text] == "abc abc"

# --- 7. schedule tools ------------------------------------------------------

sreg = Master::ToolRegistry.new
sreg.register(Master::Tools::ScheduleCreate.new(store))
sreg.register(Master::Tools::ScheduleList.new(store))
sreg.register(Master::Tools::ScheduleDelete.new(store))

sreg.dispatch("schedule_create", { "name" => "brief", "schedule" => "every:1h", "prompt" => "brief me" })
sreg.dispatch("schedule_create", { "name" => "nightly", "schedule" => "cron:0 22 * * *", "prompt" => "wrap up" })
listed = sreg.dispatch("schedule_list", {})
abort "FAIL 7a" unless listed[:jobs].size == 2
sreg.dispatch("schedule_delete", { "name" => "brief" })
abort "FAIL 7b" unless sreg.dispatch("schedule_list", {})[:jobs].size == 1
err = sreg.dispatch("schedule_create", { "name" => "nightly", "schedule" => "every:1h", "prompt" => "dup" })
abort "FAIL 7c" unless err[:error].include?("already taken")

puts "ALL SMOKE TESTS PASSED"
