# frozen_string_literal: true

require "securerandom"
require_relative "agent"

module Master
  # Thread-pool of scoped sub-agents. Each subtask gets a fresh context
  # (own thread_id in memory), a scoped tool set, and its own step budget.
  # Sub-agents can never dispatch further subtasks (guarded by tool name).
  class Subagents
    DISPATCH_TOOL_NAME = "dispatch_subtasks"

    SUBAGENT_PROMPT = <<~TEXT
      You are a MASTER sub-agent executing exactly one scoped task.
      You cannot talk to the parent agent. Use the allowed tools when they help,
      then return the result concisely and factually.
    TEXT

    def initialize(llm:, tools:, memory:, max_steps: 8, max_workers: 4)
      @llm = llm
      @tools = tools # parent registry; scoped down per run
      @memory = memory
      @max_steps = max_steps
      @max_workers = max_workers
    end

    # Single subtask. Returns { task:, answer: }.
    def run(task, tools: nil)
      { task: task, answer: run_agent(task, build_registry(tools)) }
    end

    # Several independent subtasks in parallel (bounded by max_workers).
    # Returns an array aligned with the input: { task:, answer: } or { task:, error: }.
    def run_parallel(tasks, tools: nil)
      results = Array.new(tasks.size)
      idx = 0
      tasks.each_slice(@max_workers).each do |group|
        threads = group.map do |task|
          i = idx
          idx += 1
          Thread.new { results[i] = safe_run(task, tools) }
        end
        threads.each(&:join)
      end
      results
    end

    # Registry containing only the allowed tools; dispatch_subtasks is always
    # excluded so sub-agents cannot recurse.
    def build_registry(tool_names)
      allowed = Array(tool_names).map(&:to_s)
      reg = ToolRegistry.new
      @tools.each do |tool|
        next if tool.name == DISPATCH_TOOL_NAME
        next if !allowed.empty? && !allowed.include?(tool.name)

        reg.register(tool)
      end
      reg
    end

    private

    def run_agent(task, registry)
      Agent.new(
        llm: @llm,
        tools: registry,
        memory: @memory,
        system_prompt: SUBAGENT_PROMPT,
        max_steps: @max_steps
      ).run(task, thread_id: "subagent-#{SecureRandom.hex(4)}")
    end

    def safe_run(task, tool_names)
      { task: task, answer: run_agent(task, build_registry(tool_names)) }
    rescue StandardError => e
      { task: task, error: "#{e.class}: #{e.message}" }
    end
  end
end
