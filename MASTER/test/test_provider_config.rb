# frozen_string_literal: true

require_relative "test_helper"

class TestProviderConfig < Minitest::Test
  def test_api_key_specs_are_loaded_from_yaml
    specs = Master.api_key_specs

    assert_includes specs, [:openai_api_key, "OPENAI_API_KEY", 40]
    assert_includes specs, [:gemini_api_key, "GOOGLE_API_KEY", 20]
    assert_includes specs, [:gemini_api_key, "GEMINI_API_KEY", 20]
  end

  def test_minimum_lengths_are_provider_specific
    previous = ENV["ANTHROPIC_API_KEY"]

    ENV["ANTHROPIC_API_KEY"] = "x" * 40
    refute Master.api_key_present?("ANTHROPIC_API_KEY")
    ENV["ANTHROPIC_API_KEY"] = "x" * 80
    assert Master.api_key_present?("ANTHROPIC_API_KEY")
  ensure
    ENV["ANTHROPIC_API_KEY"] = previous
  end

  # data/providers.yml and data/models.yml hold the zai route in halves: the
  # bare glm- id pattern and the key env live here, the openai_compatible base
  # lives there. Neither half may drift from the other, and this row carries no
  # ruby_llm_key on purpose - RubyLLM has no zhipu setter, the trap
  # test_provider_key_wiring exists to catch.
  def test_replicate_declares_both_custom_api_credential_names
    providers = YAML.safe_load_file(File.expand_path("../data/providers.yml", __dir__))
    row = providers.fetch("replicate")

    assert_equal %w[REPLICATE_API_TOKEN REPLICATE_API_KEY], Array(row["env"])
    refute row.key?("ruby_llm_key"), "Replicate uses its dedicated sender, not RubyLLM configuration"
  end

  def test_the_zai_route_is_coherent_across_both_halves
    providers = YAML.safe_load_file(File.expand_path("../data/providers.yml", __dir__))
    models = YAML.safe_load_file(File.expand_path("../data/models.yml", __dir__), aliases: true)

    row = providers.fetch("zai")
    assert_equal %w[ZAI_API_KEY], Array(row["env"])
    pattern = Regexp.new(row["model_pattern"])
    assert pattern.match?("glm-5.3-flash")
    refute pattern.match?("claude-sonnet-5-5")
    refute row.key?("ruby_llm_key")

    endpoint = models.dig("openai_compatible", "zai")
    assert_equal "https://api.z.ai/api/paas/v4", endpoint["base"]
    assert_equal %w[ZAI_API_KEY], Array(endpoint["key_env"])
  end

  def test_ollama_cloud_route_is_primary_and_keeps_glm_as_fallback
    providers = YAML.safe_load_file(File.expand_path("../data/providers.yml", __dir__))
    models = YAML.safe_load_file(File.expand_path("../data/models.yml", __dir__), aliases: true)

    provider = providers.fetch("ollama_cloud")
    assert_equal %w[OLLAMA_API_KEY], Array(provider["env"])
    assert Regexp.new(provider.fetch("model_pattern")).match?("ollama_cloud:deepseek-v4.1-flash")
    refute provider.key?("ruby_llm_key")

    endpoint = models.dig("openai_compatible", "ollama_cloud")
    assert_equal "https://ollama.com/v1", endpoint["base"]
    assert_equal %w[OLLAMA_API_KEY], Array(endpoint["key_env"])
    assert_equal "unknown", endpoint["privacy_posture"]

    model_id = "ollama_cloud:deepseek-v4.1-flash"
    definition = models.fetch("model_defs").fetch("ollama_deepseek_v4_1_flash")
    assert_equal model_id, definition["id"]
    assert_equal 1_000_000, definition["context_window"]

    %w[default primary strong fast].each do |tier_name|
      tier = models.fetch("models").fetch(tier_name)
      assert_equal model_id, tier.fetch(0).fetch("id"), "#{tier_name} must lead with Ollama Cloud"
      assert_equal "glm-5.3-flash", tier.fetch(1).fetch("id"), "#{tier_name} must retain GLM as fallback"
    end

    vision_ids = models.fetch("models").fetch("vision").map { |row| row.fetch("id") }
    assert_equal %w[
      google/gemini-3.1-flash-lite
      x-ai/grok-4.3
      openai/gpt-5.4
      qwen/qwen3.8-flash
    ], vision_ids
    refute_includes vision_ids, model_id, "Ollama Cloud has no verified image-input grant and must not enter the vision tier"

    reads = Regexp.new(models.dig("vision_families", "reads_images").join("|"), Regexp::IGNORECASE)
    blind = Regexp.new(models.dig("vision_families", "blind").join("|"), Regexp::IGNORECASE)
    refute reads.match?(model_id)
    assert blind.match?(model_id)
    refute_includes models.fetch("tool_capable_prefixes"), model_id,
                    "the hosted sender must use the governed ReAct fallback until native tool payloads are supported"
  end
end
