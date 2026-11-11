# frozen_string_literal: true

require "test_helper"

class ChatServiceConversationTest < ActiveSupport::TestCase
  class FakeStream
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(data)
      @writes << data.to_s
    end

    def close; end
  end

  setup do
    Fiber[:master_conversation] = nil
    @dir = Dir.mktmpdir
    @bus = Master::Trace::EventBus.new(event_log: Master::Trace::Log::Event.new(root: @dir))
    @stream = FakeStream.new
    @mine = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    @service = ChatService.new(
      container: { bus: @bus, session: nil, agent: nil },
      params: { message: "hi" },
      stream: @stream,
      logger: Rails.logger,
      tier: "visitor",
      unlocked: false,
      author: false,
      conversation: @mine,
    )
    @service.send(:subscribe_to_events)
  end

  teardown do
    Fiber[:master_conversation] = nil
    FileUtils.rm_rf(@dir)
  end

  test "sse handlers write this conversation and skip everyone else's" do
    Fiber[:master_conversation] = @mine
    @bus.publish("tool:before", tool: "Write", path: "/tmp/ours.rb")
    ours = @stream.writes.dup

    Fiber[:master_conversation] = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    @bus.publish("tool:before", tool: "Write", path: "/tmp/theirs.rb")
    Fiber[:master_conversation] = nil
    @bus.publish("scan:complete", count: 9)

    assert ours.any? { |chunk| chunk.include?("ours.rb") || chunk.include?("Write") }
    assert_equal ours, @stream.writes
    refute @stream.writes.join.include?("theirs.rb")
  end


  test "semantic subject SSE sidecars are bounded and scoped to their conversation" do
    Fiber[:master_conversation] = @mine
    @bus.publish(
      "assistant:visual-subject",
      text: "A bicycle has a frame and two wheels.",
      visual_subject: {
        kind: "custom",
        label: "bicycle",
        confidence: 0.88,
        sequence: ["frame", "wheel"],
        parts: [
          { key: "frame", primitive: "beam", axis: "x", center: [0, 0, 0], size: [0.4, 0.03, 0.03] },
          { key: "wheel", primitive: "ring", center: [0.3, -0.2, 0], size: [0.2, 0.2, 0.02] }
        ]
      }
    )
    event = @stream.writes.find { |chunk| chunk.start_with?("event: visual_subject") }

    refute_nil event
    payload = JSON.parse(event.split("data: ", 2).last)
    assert_equal "A bicycle has a frame and two wheels.", payload.fetch("text")
    assert_equal "custom", payload.dig("visual_subject", "kind")
    assert_equal %w[frame wheel], payload.dig("visual_subject", "sequence")
    assert_equal 2, payload.dig("visual_subject", "parts").size

    own_writes = @stream.writes.dup
    Fiber[:master_conversation] = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    @bus.publish(
      "assistant:visual-subject",
      text: "A private subject",
      visual_subject: { kind: "custom", parts: [] }
    )
    Fiber[:master_conversation] = nil

    assert_equal own_writes, @stream.writes
    refute_includes @stream.writes.join, "private subject"
  end
  test "the model event names the model that answered, not the one routed first" do
    Fiber[:master_conversation] = @mine
    @bus.publish("llm:request", model: "routed/first-choice", tokens: 3)
    @bus.publish("llm:response", model: "fallback/answered", success: true, tokens_approx: 9)

    models = @stream.writes.select { |chunk| chunk.start_with?("event: model") }
    assert_equal 1, models.size
    assert_includes models.first, "fallback/answered"
  end
end
