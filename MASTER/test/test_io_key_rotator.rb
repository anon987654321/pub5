# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"

# A provider's quota boundary is not multiplied by credentials. KeyRotator
# selects one stable credential per provider and refuses distinct populated
# credentials rather than switching identities after a limit response.
class KeyRotatorTest < Minitest::Test
  Rotator = Master::Io::KeyRotator
  TWO_VARS = %w[TEST_ROTATOR_KEY_A TEST_ROTATOR_KEY_B].freeze
  OPENROUTER_VARS = %w[OPENROUTER_API_KEY OPENROUTER_API_KEY_2 OPENROUTER_API_KEY_3].freeze

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def long(seed) = seed * Master::MIN_API_KEY_LENGTH_HEURISTIC

  def openrouter_env_vars
    (Array(Master.models_config.dig("openrouter", "keys_env")) + OPENROUTER_VARS).uniq
  end

  def test_env_vars_come_from_models_yml_or_fall_back
    with_env(openrouter_env_vars.to_h { |var| [var, nil] }) do
      assert_includes Rotator.env_vars, "OPENROUTER_API_KEY"
    end
  end

  def test_keys_ignores_unset_and_too_short_values
    with_env(TWO_VARS.to_h { |var| [var, nil] }.merge(TWO_VARS.first => "short")) do
      Rotator.stub(:env_vars, TWO_VARS) { assert_empty Rotator.keys }
    end
  end

  def test_duplicate_environment_aliases_for_the_same_credential_are_one_key
    with_env(TWO_VARS.to_h { |var| [var, long("a")] }) do
      Rotator.stub(:env_vars, TWO_VARS) do
        assert_equal [long("a")], Rotator.keys
        assert_equal long("a"), Rotator.active_key
      end
    end
  end

  def test_active_key_is_nil_without_any_configured_key
    with_env(TWO_VARS.to_h { |var| [var, nil] }) do
      Rotator.stub(:env_vars, TWO_VARS) { assert_nil Rotator.active_key }
    end
  end

  def test_active_key_stays_stable_and_quota_rotation_is_a_noop
    with_env(TWO_VARS.to_h { |var| [var, nil] }.merge(TWO_VARS.first => long("a"))) do
      Rotator.stub(:env_vars, TWO_VARS) do
        3.times do
          assert_equal long("a"), Rotator.active_key
          refute Rotator.rotate_for("openrouter/some-model:free")
          refute Rotator.rotate_for("openrouter/some-model")
        end
        assert_equal long("a"), Rotator.active_key
        assert_equal 0, Rotator.positions("openrouter")
      end
    end
  end

  def test_distinct_populated_credentials_for_one_provider_are_rejected
    values = { TWO_VARS[0] => long("a"), TWO_VARS[1] => long("b") }
    with_env(values) do
      Rotator.stub(:env_vars, TWO_VARS) do
        error = assert_raises(ArgumentError) { Rotator.active_key }
        assert_match(/multiple distinct populated credentials/, error.message)
      end
    end
  end

  def test_configured_openrouter_aliases_reject_distinct_secrets
    Master.stub(:models_config, { "openrouter" => { "keys_env" => TWO_VARS } }) do
      values = openrouter_env_vars.to_h { |var| [var, nil] }
      values.merge!(TWO_VARS[0] => long("a"), TWO_VARS[1] => long("b"))
      with_env(values) do
        error = assert_raises(ArgumentError) { Rotator.env_vars }
        assert_match(/multiple distinct populated credentials/, error.message)
      end
    end
  end

  def test_one_legacy_openrouter_credential_remains_usable
    values = openrouter_env_vars.to_h { |var| [var, nil] }
    values["OPENROUTER_API_KEY_2"] = long("o")
    with_env(values) { assert_equal long("o"), Rotator.active_key }
  end

  def test_hosted_provider_selector_keeps_a_single_credential
    with_env(TWO_VARS.to_h { |var| [var, nil] }.merge(TWO_VARS.first => long("c"))) do
      Rotator.stub(:hosted_env_vars, TWO_VARS) do
        assert_equal long("c"), Rotator.active_key_for("cerebras")
        refute Rotator.rotate_for("cerebras:llama-3.3-70b")
      end
    end
  end
end
