# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"

# Hosted free-tier caps are provider-scoped. Credential failover must cross
# providers, never rotate keys within one provider.
class TestHostedFreeTiers < Minitest::Test
  Quota = Master::Io::ModelQuota
  Rotator = Master::Io::KeyRotator

  CONFIG = {
    "openrouter" => { "daily_quota_per_model" => 50 },
    "openai_compatible" => {
      "cerebras" => { "base" => "https://api.cerebras.ai/v1", "key_env" => %w[TEST_CEREBRAS_A TEST_CEREBRAS_B],
                      "daily_quota" => 100 },
      "nvidia" => { "base" => "https://integrate.api.nvidia.com/v1", "key_env" => %w[TEST_NVIDIA_A] },
    },
  }.freeze

  def long(seed) = seed * Master::MIN_API_KEY_LENGTH_HEURISTIC

  def test_a_capped_endpoint_counts_its_lanes_against_its_own_cap
    Master.stub(:models_config, CONFIG) do
      assert Quota.trackable?("cerebras:llama-3.3-70b")
      assert_equal 100, Quota.daily_limit_for("cerebras:llama-3.3-70b")
      Quota.stub(:count, 100) { assert Quota.over_quota?("cerebras:llama-3.3-70b") }
      Quota.stub(:count, 99) { refute Quota.over_quota?("cerebras:llama-3.3-70b") }
    end
  end

  def test_an_endpoint_without_a_cap_and_a_free_slug_keep_their_rules
    Master.stub(:models_config, CONFIG) do
      refute Quota.trackable?("nvidia:z-ai/glm-5.3-flash"), "no documented cap, no guessed one"
      assert_equal 50, Quota.daily_limit_for("nvidia/nemotron-3-super-120b-a12b:free")
    end
  end

  def with_two_keys
    saved = %w[TEST_CEREBRAS_A TEST_CEREBRAS_B].to_h { |var| [var, ENV.fetch(var, nil)] }
    ENV["TEST_CEREBRAS_A"] = long("a")
    ENV["TEST_CEREBRAS_B"] = long("b")
    Master.stub(:models_config, CONFIG) { yield }
  ensure
    saved.each { |var, value| value.nil? ? ENV.delete(var) : ENV[var] = value }
  end

  def test_multiple_populated_keys_for_one_provider_are_refused
    with_two_keys do
      error = assert_raises(ArgumentError) { Rotator.active_key_for("cerebras") }
      assert_includes error.message, "multiple populated credentials"
      refute Rotator.rotate_for("cerebras:llama-3.3-70b")
    end
  end

  def test_multiple_openrouter_credentials_are_refused
    names = %w[OPENROUTER_API_KEY OPENROUTER_API_KEY_2 OPENROUTER_API_KEY_3]
    saved = names.to_h { |var| [var, ENV.fetch(var, nil)] }
    ENV.delete(names.first)
    ENV[names[1]] = long("o")
    ENV[names[2]] = long("p")
    Master.stub(:models_config, CONFIG) do
      error = assert_raises(ArgumentError) { Rotator.active_key }
      assert_includes error.message, "multiple populated credentials"
    end
  ensure
    saved.each { |var, value| value.nil? ? ENV.delete(var) : ENV[var] = value }
  end

  def test_one_legacy_openrouter_credential_remains_usable
    names = %w[OPENROUTER_API_KEY OPENROUTER_API_KEY_2 OPENROUTER_API_KEY_3]
    saved = names.to_h { |var| [var, ENV.fetch(var, nil)] }
    names.each { |var| ENV.delete(var) }
    ENV[names[1]] = long("o")
    Master.stub(:models_config, CONFIG) do
      assert_equal long("o"), Rotator.active_key
    end
  ensure
    saved.each { |var, value| value.nil? ? ENV.delete(var) : ENV[var] = value }
  end

  def test_a_single_key_is_used_without_rotation
    saved = ENV.fetch("TEST_NVIDIA_A", nil)
    ENV["TEST_NVIDIA_A"] = long("n")
    Master.stub(:models_config, CONFIG) do
      assert_equal long("n"), Rotator.active_key_for("nvidia")
      refute Rotator.rotate_for("nvidia:z-ai/glm-5.3-flash")
    end
  ensure
    saved.nil? ? ENV.delete("TEST_NVIDIA_A") : ENV["TEST_NVIDIA_A"] = saved
  end
end
