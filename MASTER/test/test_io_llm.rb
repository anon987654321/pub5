# frozen_string_literal: true

require_relative "test_helper"
require "io/llm"

class IoLlmTest < Minitest::Test
  def test_llm_tool_forwarding_source_compiles
    path = File.expand_path("../lib/io/llm.rb", __dir__)
    source = File.read(path)
    assert_silent { RubyVM::InstructionSequence.compile(source, path) }
  end

  def test_failed_tool_reply_redacts_provider_credentials
    forwarding = Object.new.extend(Master::Io::LLM::ToolForwarding)
    forwarding.instance_variable_set(:@tool, Object.new)
    result = Struct.new(:message).new("provider rejected request: sk-#{'A' * 24}")

    previous = ENV["MASTER_LLM_RECORD"]
    ENV["MASTER_LLM_RECORD"] = "0"
    reply = forwarding.send(
      :finish_tool_failure,
      result:, args: {}, invocation_id: "test-invocation", outcome: "error", ms: 1, identity: nil
    )

    assert_equal "Error: provider rejected request: [REDACTED]", reply
  ensure
    previous.nil? ? ENV.delete("MASTER_LLM_RECORD") : ENV["MASTER_LLM_RECORD"] = previous
  end
end
