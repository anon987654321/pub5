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
end
