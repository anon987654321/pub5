# frozen_string_literal: true

require "json"

require_relative "master/llm_adapter"
require_relative "master/memory"
require_relative "master/vector_memory"
require_relative "master/schedule_store"
require_relative "master/scheduler"
require_relative "master/tool_registry"
require_relative "master/agent"
require_relative "master/subagents"

require_relative "master/tools/web_fetch"
require_relative "master/tools/web_search"
require_relative "master/tools/browser"
require_relative "master/tools/shell"
require_relative "master/tools/data"
require_relative "master/tools/memory_tools"
require_relative "master/tools/schedule_tools"
require_relative "master/tools/dispatch"

module Master
  VERSION = "0.2.0"
end
