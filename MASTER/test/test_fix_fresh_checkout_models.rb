# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"

class TestFixFreshCheckoutModels < Minitest::Test
  PRIMARY = "ollama_cloud:deepseek-v4.1-flash"
  GLM_FALLBACK = "glm-5.3-flash"

  def setup
    @env_keys = %w[
      OLLAMA_API_KEY ZAI_API_KEY OPENROUTER_API_KEY MASTER_MODEL MASTER_NO_GROK_CLI
      MASTER_NO_AGY_CLI MASTER_NO_OLLAMA MASTER_NO_POOL_PROBES
    ]
    @saved_env = @env_keys.to_h { |key| [key, ENV[key]] }
    ENV.delete("OLLAMA_API_KEY")
    ENV["ZAI_API_KEY"] = "zai-" + ("a" * 48)
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-" + ("a" * 64)
    ENV["MASTER_NO_GROK_CLI"] = "1"
    ENV["MASTER_NO_AGY_CLI"] = "1"
    ENV["MASTER_NO_OLLAMA"] = "1"
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    @router = Master::CLI::Routing::ModelRouter.new(
      config: Master::TestSupport::FakeConfig.new(model: "nvidia/nemotron-3-ultra-550b-a55b:free"),
      root: Master::ROOT,
    )
  end

  def teardown
    @saved_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Master::Io::LaneSelection.reset_hosted_resolver!
  end

  def test_ollama_cloud_is_first_and_glm_is_the_immediate_fallback_in_fix_tiers
    models = Master.models_config(root: Master::ROOT).fetch("models")
    %w[default primary strong].each do |tier|
      assert_equal PRIMARY, models.fetch(tier).first.fetch("id"), "#{tier} tier must lead with Ollama Cloud"
      assert_equal GLM_FALLBACK, models.fetch(tier).fetch(1).fetch("id"), "#{tier} tier must retain GLM immediately after it"
    end
  end

  def test_fresh_router_uses_glm_when_ollama_cloud_is_not_configured
    chain = @router.fallback_chain(task_type: :code_generation)
    assert_equal GLM_FALLBACK, chain.first
    assert_equal :free, Master::Io::LaneSelection.kind(chain.last)
  end

  def test_model_picker_uses_glm_when_the_ollama_cloud_key_is_absent
    assert_equal GLM_FALLBACK, @router.pool(wait: false).first
  end

  def test_boot_default_uses_glm_fallback_when_ollama_cloud_is_unavailable
    assert_equal GLM_FALLBACK, Master.default_model
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
