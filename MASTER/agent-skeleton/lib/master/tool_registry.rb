# frozen_string_literal: true

module Master
  class ToolError < StandardError; end

  # ------------------------------------------------------------------
  # Tool interface: subclass and implement the four methods.
  #
  #   class SayHello < Master::Tool
  #     def name         = "say_hello"        # (use regular defs if < Ruby 3.0)
  #     def description  = "Says hello to someone."
  #     def parameters                        # JSON Schema for the arguments
  #       { type: "object",
  #         properties: { who: { type: "string" } },
  #         required: ["who"] }
  #     end
  #     def call(args)                        # args: Hash with string keys
  #       { message: "Hello, #{args.fetch('who')}!" }
  #     end
  #   end
  #
  # `call` may return any JSON-serializable value (Hash, Array, String, ...).
  # ------------------------------------------------------------------
  class Tool
    def name
      raise NotImplementedError
    end

    def description
      raise NotImplementedError
    end

    def parameters
      raise NotImplementedError
    end

    def call(_args)
      raise NotImplementedError
    end

    # OpenAI function-calling schema consumed by LLMAdapter#chat(tools:).
    def to_openai_schema
      {
        type: "function",
        function: {
          name: name,
          description: description,
          parameters: parameters
        }
      }
    end
  end

  class ToolRegistry
    include Enumerable

    def initialize
      @tools = {}
    end

    def register(tool)
      raise ToolError, "tool must be a Master::Tool" unless tool.is_a?(Tool)
      raise ToolError, "duplicate tool name: #{tool.name}" if @tools.key?(tool.name)

      @tools[tool.name] = tool
      self
    end

    def each(&block)
      @tools.each_value(&block)
    end

    def [](name)
      @tools[name]
    end

    # Tool schemas handed to the LLM on every chat call.
    def schemas
      @tools.values.map(&:to_openai_schema)
    end

    # Never raises on failure: errors are returned as a result so the agent
    # loop can feed them back to the model (retry, pick another tool, or
    # explain to the user) instead of crashing the run.
    def dispatch(name, args)
      tool = @tools[name]
      return { error: "unknown tool: #{name}" } unless tool

      validate!(tool, args)
      tool.call(args || {})
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}" }
    end

    private

    def validate!(tool, args)
      schema = tool.parameters || {}
      required = Array(schema[:required] || schema["required"] || []).map(&:to_s)
      keys = (args || {}).keys.map(&:to_s)
      missing = required - keys
      unless missing.empty?
        raise ToolError, "missing required arguments for #{tool.name}: #{missing.join(', ')}"
      end
    end
  end
end
