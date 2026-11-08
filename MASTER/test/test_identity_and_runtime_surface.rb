# frozen_string_literal: true

require_relative "test_helper"

# Open rows 1 and 2 of docs/session-2026-11-08.md. The transcript showed a
# runtime whose answers followed the serving lane: it introduced itself as
# "Grok 4.7, from xAI." and later "I'm Glyph Cluster" as lanes moved under it,
# and it denied capabilities the runtime had - no tool could play speech while
# voice0 was on, and it could not see any output while the probe, read and
# shell tools were inside the fold. The prompt is where both are answered:
# the identity block pins who is speaking independent of any lane, and the
# runtime surface names the registered commands and the live voice state so
# what the model can do is what the prompt says it can do.
class TestIdentityAndRuntimeSurface < Minitest::Test
  LANES = ["grok-cli:auto", "kilo:stealth/glyph-cluster", "ollama:gemma3:4b"].freeze

  def identity_block(prompt)
    prompt[/\<master_identity>.*?<\/master_identity>/m]
  end

  # The identity block is the one place that pins who is speaking, so it must
  # be byte-identical whatever lane serves the turn: no lane id, vendor or
  # model string is interpolated into it.
  def test_the_identity_block_is_byte_identical_across_lanes
    blocks = LANES.map do |lane|
      ENV["MASTER_MODEL"] = lane
      identity_block(Master::Voice::Personality.new.send(:build_system_prompt))
    end

    assert blocks.all? { |block| block.is_a?(String) && !block.empty? }, "every prompt carries an identity block"
    assert_equal 1, blocks.uniq.size, "the identity block moved with the lane"
    blocks.each { |block| assert_block_is_lane_independent(block) }
  ensure
    ENV.delete("MASTER_MODEL")
  end

  def assert_block_is_lane_independent(block)
    assert_includes block, "transport, not identity"
    assert_includes block, "answer MASTER and its version"
    LANES.each do |lane|
      refute_includes block, lane.sub(/\A.*:/, ""), "the identity block names the serving lane"
      refute_includes block, lane.split(":").first, "the identity block names the lane's provider"
    end
  end

  # The runtime surface reads the registered command set rather than restating
  # it, so a command that leaves the registry cannot be advertised in the prompt.
  def test_the_runtime_surface_names_only_registered_commands
    prompt = agent_prompt

    assert_includes prompt, "<master_runtime_surface>"
    surface = prompt[/\<master_runtime_surface>(.*?)<\/master_runtime_surface>/m, 1]
    advertised = surface.scan(%r{/([a-z][a-z0-9_-]*)}i).flatten.map(&:downcase).uniq
    registered = Master::CLI::CommandRegistry::HELP_TOPICS.keys

    assert advertised.any?, "the surface names no commands"
    assert_empty advertised - registered, "the prompt advertises an unregistered command"
    assert_includes advertised, "voice", "the speech control the transcript needed is not named"
    assert_includes advertised, "help"
  end

  # The transcript's model said no tool could play audio while voice0 was on.
  # The surface must carry the session's actual speech state, from the one
  # source that decides it.
  def test_the_runtime_surface_names_the_live_voice_state
    prompt = agent_prompt

    assert_match(/Speech: replies (?:stay text this session|are spoken aloud this session)/, prompt)
    assert_includes prompt, Master::Voice::Playback.enabled? ? "are spoken aloud" : "stay text this session"
  end

  # The transcript's model said it could not see the terminal. The honest
  # boundary: recorded output is readable, a live screen is not.
  def test_the_runtime_surface_names_the_output_boundary
    assert_includes agent_prompt, "you cannot watch the operator's screen"
    assert_includes agent_prompt, "run governed shell commands and read their recorded output"
  end

  private

  FakeConfig = Struct.new(:model, :task_type, :reasoning_mode) do
    def [](name) = respond_to?(name) ? public_send(name) : nil
  end
  FakeSession = Struct.new(:messages) { def add_message(**) = messages << _1 }
  FakeCB = Struct.new(:out) { def check_rate!; end; def call(_, &block); block.call; end }
  FakeCache = Struct.new(:store) { def fetch(name, _mode, &block); (store[name] ||= block.call); end }

  def agent_prompt
    agent = Master::Review::Agent.new(deps: Master::Review::Agent::Dependencies.from_kwargs(
      config:          FakeConfig.new("claude-sonnet-4-6", :exploration, "none"),
      session:         FakeSession.new([]),
      tools:           [],
      circuit_breaker: FakeCB.new,
      cache:           FakeCache.new({}),
    ))
    agent.send(:dynamic_prompt)
  end
end
