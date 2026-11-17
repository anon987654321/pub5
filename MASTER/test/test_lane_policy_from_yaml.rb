# frozen_string_literal: true

require_relative "test_helper"

# Lane policy that was held twice in Ruby now has one owner in YAML: vision
# families and subscription order in models.yml, key routing in providers.yml.
class TestLanePolicyFromYaml < Minitest::Test
  Selection = Master::Io::LaneSelection

  # A bare gemini-3 id reads images; a blind family never does; the dispatcher
  # asks the same reader.
  def test_vision_families_cover_every_gemini_and_the_dispatcher_agrees
    assert Selection.vision?("gemini-3.1-pro")
    refute Selection.vision?("deepseek-chat")

    dispatcher = Master::Review::LLMDispatcher.allocate
    assert dispatcher.send(:vision_capable?, "gemini-3.1-pro")
  end

  def test_subscription_lanes_come_from_models_yml
    assert_equal %w[grok-cli codex-cli agy zai-cli], Selection.subscription_lanes
  end

  # Operator, 2026-11-16: a /fix run reaches the paid DeepSeek API and the
  # all-hands gateway before the free floor, so a host with only DEEPSEEK_API_KEY
  # answers on it rather than crawling the free tier.
  def test_the_default_and_primary_tiers_lead_the_paid_deepseek_lane
    %w[default primary].each do |name|
      tier = Selection.tier(name)
      deepseek = tier.index { |id| id.start_with?("deepseek") }
      refute_nil deepseek, "#{name} lists a deepseek lane"
      assert_operator deepseek, :<, tier.index { |id| Selection.kind(id) == :free } || tier.size
    end
  end

  # An owner/name id goes through OpenRouter, a bare id through its vendor.
  def test_api_key_routing_comes_from_providers_yml
    envs = ->(id) { Selection.api_keys.find { |pattern, _envs| pattern.match?(id) }&.last }

    assert_equal %w[OPENROUTER_API_KEY], envs.call("deepseek/deepseek-chat")
    assert_equal %w[DEEPSEEK_API_KEY], envs.call("deepseek-chat")
    assert_equal %w[GOOGLE_API_KEY GEMINI_API_KEY], envs.call("gemini-3.1-pro")
    assert_nil envs.call("mistral-large")
  end

  def test_configured_anthropic_and_gemini_apis_are_in_the_default_premier_pool
    %w[default primary].each do |name|
      tier = Selection.tier(name)
      assert_includes tier, "claude-opus-5-5"
      assert_includes tier, "claude-sonnet-5-5"
      assert_includes tier, "gemini-2.5-flash"
    end
  end

  def test_operator_configured_provider_credentials_are_wired_without_renaming
    envs = ->(id) { Selection.api_keys.find { |pattern, _names| pattern.match?(id) }&.last }
    assert_equal %w[ANTHROPIC_API_KEY], envs.call("claude-sonnet-5-5")
    assert_equal %w[GOOGLE_API_KEY GEMINI_API_KEY], envs.call("gemini-2.5-flash")
    assert_equal %w[OPENROUTER_API_KEY], envs.call("openai/gpt-4o")

    providers = Master.load_yaml(File.join(Master::ROOT, "data", "providers.yml"))
    assert_equal %w[REPLICATE_API_TOKEN REPLICATE_API_KEY], providers.dig("replicate", "env")
  end

  # Perplexity stays out of hosted discovery until its product and provider-specific
  # request/response contract have been deliberately selected and tested.
  def test_perplexity_is_not_a_routable_hosted_provider
    config = Selection.config

    refute_includes config.fetch("openai_compatible").keys, "perplexity"
  end

  # Reachability for a signed-in subscription CLI is prefix-based: a lane that
  # joins the catalogue without its prefix in KEYLESS_LANE_PREFIXES is refused
  # at refusal_before_send on any host with no API key ("No API keys
  # configured"), the lane probe records it dead, and /fix drops its primary
  # lane for the whole run. zai-cli did exactly that (2026-11-17).
  def test_every_remote_cli_lane_is_reachable_without_a_key
    prefixes = Master::MasterRuntime::KEYLESS_LANE_PREFIXES

    Master.cli_lanes.each do |name, lane|
      next if lane["kind"] == "local"

      assert_includes prefixes, "#{name}:",
        "#{name} is a signed-in subscription lane; its prefix must ride KEYLESS_LANE_PREFIXES"
    end
  end

  # The fix pipeline's availability gate refuses a run whose routing pick is
  # free-class while a subscription lane is live, so the router's tier chains
  # must carry every remote subscription lane the catalogue offers -- unless
  # the lane is deliberately dead by hand in data/lanes.yml (codex-cli today:
  # excluded from automatic selection until a bounded execution probe proves
  # a live response). A reachable, chain-less, non-dead lane gets its run
  # refused as "routing disagrees with provider availability" before the
  # first file.
  def test_every_remote_cli_lane_appears_in_a_tier_chain_or_is_dead_by_hand
    tier_ids = Master.models_config(root: Master::ROOT).fetch("models").values
                   .flatten.filter_map { |row| row.is_a?(Hash) ? row["id"] : nil }
    dead = Master.load_yaml(Master.data_path("../data/lanes.yml")).fetch("dead", [])
           .map { |name| "#{name}:" }

    Master.cli_lanes.each do |name, lane|
      next if lane["kind"] == "local"

      carried = tier_ids.any? { |id| id.to_s.start_with?("#{name}:") }
      assert(
        carried || dead.include?("#{name}:"),
        "#{name} is a subscription lane no tier chain carries and data/lanes.yml does not declare dead"
      )
    end
  end
end
