# frozen_string_literal: true

require_relative "../subagents"

module Master
  module Tools
    # Fan-out tool: the top-level agent hands one or more independent
    # subtasks to thread-pooled sub-agents with scoped tool access.
    class DispatchSubtasks < Tool
      def initialize(subagents)
        @subagents = subagents
      end

      def name
        Master::Subagents::DISPATCH_TOOL_NAME
      end

      def description
        "Run one or more independent subtasks in isolated sub-agents (fresh context, scoped " \
          "tools, no ability to dispatch further subtasks). Use for fan-out work such as " \
          "parallel research or per-file inspection. Results come back aligned with the task list."
      end

      def parameters
        {
          type: "object",
          properties: {
            tasks: {
              type: "array",
              items: { type: "string" },
              description: "One or more self-contained subtask descriptions"
            },
            tools: {
              type: "array",
              items: { type: "string" },
              description: "Tool names sub-agents may use; default is all except this one"
            }
          },
          required: ["tasks"]
        }
      end

      def call(args)
        tasks = Array(args.fetch("tasks")).map(&:to_s).reject(&:empty?)
        raise ArgumentError, "at least one task is required" if tasks.empty?

        @subagents.run_parallel(tasks, tools: args["tools"])
      end
    end
  end
end
