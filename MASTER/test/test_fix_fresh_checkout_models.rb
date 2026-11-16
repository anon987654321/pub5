# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"

class TestFixFreshCheckoutModels < Minitest::Test
  PRIMARY = "glm-5.3-flash"

  def setup
    @env_keys = %w[
      ZAI_API_KEY OPENROUTER_API_KEY MASTER_MODEL MASTER_NO_GROK_CLI
      MASTER_NO_AGY_CLI MASTER_NO_OLLAMA MASTER_NO_POOL_PROBES
    ]
    @saved_env = @env_keys.to_h { |key| [key, ENV[key]] }
    ENV["ZAI_API_KEY"] = "zai-" + ("a" * 48)
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-" + ("a" * 64)
    ENV["MASTER_NO_GROK_CLI"] = "1"
    ENV["MASTER_NO_AGY_CLI"] = "1"
    ENV["MASTER_NO_OLLAMA"] = "1"
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    @router = Master::CLI::Routing::ModelRouter.new(
      config: Master::TestSupport::FakeConfig.new(model: "nvidia/nemotron-3-super-120b-a12b:free"),
      root: Master::ROOT,
    )
  end

  def teardown
    @saved_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Master::Io::LaneSelection.reset_hosted_resolver!
  end

  def test_glm_is_the_first_model_in_the_live_fix_tiers
    models = Master.models_config(root: Master::ROOT).fetch("models")
    %w[default primary strong].each do |tier|
      assert_equal PRIMARY, models.fetch(tier).first.fetch("id"), "#{tier} tier must keep glm-5.3-flash first"
    end
  end

  def test_fresh_router_uses_glm_for_code_generation
    chain = @router.fallback_chain(task_type: :code_generation)
    assert_equal PRIMARY, chain.first
    assert_equal :free, Master::Io::LaneSelection.kind(chain.last)
  end

  def test_boot_default_uses_glm_when_its_provider_key_is_present
    assert_equal PRIMARY, Master.default_model
  end

  def test_generic_cli_lanes_remain_available
    config = Master.models_config(root: Master::ROOT)
    assert_includes config.fetch("subscription_lanes"), "grok-cli"
    assert config.fetch("cli_lanes").key?("grok-cli")
  end

  def test_anthropic_api_models_remain_available
    definitions = Master.models_config(root: Master::ROOT).fetch("model_defs")
    assert definitions.values.any? { |row| row["id"] == "claude-opus-5-5" }
    assert definitions.values.any? { |row| row["id"] == "claude-sonnet-5-5" }
  end

  def test_routing_tiers_do_not_repeat_model_ids
    models = Master.models_config(root: Master::ROOT).fetch("models")
    models.each do |tier, rows|
      ids = rows.map { |row| row.fetch("id") }
      assert_equal ids.uniq, ids, "#{tier} tier repeats a model"
    end
  end
end
