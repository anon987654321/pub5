# frozen_string_literal: true

require_relative "test_helper"
require "cli/session"

# The model's greeting arrives seconds after boot. Once the operator has started a turn it is stale, and
# printed then it ran onto the end of the first reply.
class TestCliGreeting < Minitest::Test
  Refs = Struct.new(:agent, :renderer, :bus)

  Agent = Struct.new(:reply) do
    def ask_once(*, **) = reply
  end

  Renderer = Class.new do
    def render(text, **) = text
  end

  # The session's greeting with its terminal and prompt replaced, and the start of a turn settable.
  class GreetingSession < Master::CLI::Session
    public :deliver_greeting
    attr_reader :printed

    def initialize(reply, turn_started:)
      @refs = Refs.new(Agent.new(reply), Renderer.new, nil)
      @pipeline_thread = Thread.new { nil } if turn_started
      @printed = []
    end

    def terminal_puts(line) = @printed << line
    def greeting_prompt = "greet"
  end

  def test_the_greeting_prints_before_any_turn
    session = GreetingSession.new("Natt, Johann.", turn_started: false)
    session.deliver_greeting

    assert_equal ["Natt, Johann."], session.printed
  end

  def test_a_greeting_that_arrives_after_the_first_turn_stands_down
    session = GreetingSession.new("Late for hard conversations.", turn_started: true)
    session.deliver_greeting

    assert_empty session.printed
  end

  def test_opt_in_greeting_prompt_does_not_quote_or_infer_private_history
    session = Master::CLI::Session.allocate
    Master::CLI::Welcome.stub(:context, { time: "Sunday 20:00", line: "last session 2h ago" }) do
      prompt = session.send(:greeting_prompt)
      refute_includes prompt, "last_message"
      refute_includes prompt, "personal history"
      refute_includes prompt, "depression"
      assert_includes prompt, "Do not ask a question"
    end
  end
end
