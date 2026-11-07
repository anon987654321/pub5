# frozen_string_literal: true

require_relative "test_helper"
require "time"

class ModelQuotaForecastTest < Minitest::Test
  Check = Master::Io::ModelQuota

  def test_missing_openrouter_quota_uses_the_conservative_fifty_request_default
    Master.stub(:models_config, {}) do
      assert_equal 50, Check.daily_limit
    end
  end

  def test_openrouter_quota_override_remains_authoritative
    Master.stub(:models_config, { "openrouter" => { "daily_quota_per_model" => 17 } }) do
      assert_equal 17, Check.daily_limit
    end
  end

  def test_forecast_projects_current_burn_to_the_whole_day
    now = Time.utc(2026, 9, 28, 12, 0, 0)

    Check.stub(:trackable?, true) do
      Check.stub(:daily_limit, 200) do
        Check.stub(:count, 100) do
          forecast = Check.forecast("demo:free", now:)
          assert_equal 100, forecast[:used]
          assert_equal 100, forecast[:remaining]
          assert_in_delta 200, forecast[:projected_daily], 0.01
          assert_in_delta 12, forecast[:exhaustion_hours], 0.01
        end
      end
    end
  end

  def test_burn_risk_turns_on_before_hard_exhaustion
    now = Time.utc(2026, 9, 28, 20, 0, 0)

    Check.stub(:trackable?, true) do
      Check.stub(:daily_limit, 200) do
        Check.stub(:count, 135) do
          assert Check.burn_risk?("demo:free", now:)
        end
      end
    end
  end

  # vm23's deploy boot check runs as another user than the daemon that writes this file
  # owner-only; it must start from an empty day there, while corrupt state still stops it.
  def test_a_quota_file_this_process_may_not_read_is_an_empty_day_and_a_corrupt_one_raises
    Dir.mktmpdir do |dir|
      path = File.join(dir, "model_quota.json")
      File.write(path, "{}")
      # The private-state rule, so the read itself is what fails.
      File.chmod(0o600, path)

      Check.stub(:path, path) do
        File.stub(:read, ->(*) { raise Errno::EACCES, path }) { assert_equal 0, Check.count("demo:free") }
        File.write(path, "{ not json")
        assert_raises(RuntimeError) { Check.count("demo:free") }
      end
    end
  end

  def test_non_trackable_model_has_no_forecast
    refute Check.forecast("claude-cli:opus")
    refute Check.burn_risk?("claude-cli:opus")
  end

  # The provider's own answer outranks the burn forecast: the key endpoint
  # reports what is actually left, and a forecast must never overwrite it.
  def test_a_provider_reading_is_the_authoritative_remaining
    Dir.mktmpdir do |dir|
      Check.stub(:path, File.join(dir, "model_quota.json")) do
        now = Time.utc(2026, 11, 8, 10, 0, 0)
        Check.stub(:active_openrouter_key, "test-key") do
          Check.stub(:fetch_free_model_daily_requests, 7) do
            assert_equal :refreshed, Check.refresh_from_provider!(now:, day: "2026-11-08")
          end
        end

        Check.stub(:trackable?, true) do
          Check.stub(:count, 3) do
            Check.stub(:daily_limit, 50) do
              assert_equal 7, Check.remaining("demo:free", day: "2026-11-08")
              assert_equal 7, Check.forecast("demo:free", now:)[:remaining]
              assert_equal "provider", Check.forecast("demo:free", now:)[:remaining_source]
              refute Check.over_quota?("demo:free")

              Check.stub(:active_openrouter_key, "test-key") do
                Check.stub(:fetch_free_model_daily_requests, 0) do
                  assert_equal :refreshed, Check.refresh_from_provider!(now: now + 3600, day: "2026-11-08")
                end
              end
              assert Check.over_quota?("demo:free", day: "2026-11-08"), "the provider says nothing is left"
              assert_equal 0, Check.forecast("demo:free", now: now + 3600, day: "2026-11-08")[:remaining]
            end
          end
        end
      end
    end
  end

  def test_without_a_fresh_reading_the_burn_forecast_stands_and_says_so
    Dir.mktmpdir do |dir|
      Check.stub(:path, File.join(dir, "model_quota.json")) do
        Check.stub(:trackable?, true) do
          Check.stub(:count, 10) do
            Check.stub(:daily_limit, 50) do
              forecast = Check.forecast("demo:free")
              assert_equal 40, forecast[:remaining]
              assert_equal "burn_forecast", forecast[:remaining_source]
            end
          end
        end
      end
    end
  end

  def test_the_reading_belongs_to_its_day_and_expires_with_it
    Dir.mktmpdir do |dir|
      Check.stub(:path, File.join(dir, "model_quota.json")) do
        now = Time.utc(2026, 11, 8, 10, 0, 0)
        Check.stub(:active_openrouter_key, "test-key") do
          Check.stub(:fetch_free_model_daily_requests, 7) { Check.refresh_from_provider!(now:, day: "2026-11-08") }
        end

        Check.stub(:trackable?, true) do
          assert_equal 7, Check.remaining("demo:free", day: "2026-11-08")
          assert_nil Check.provider_remaining("demo:free", day: "2026-11-09"), "yesterday's reading is not today's"
        end
      end
    end
  end

  def test_refresh_without_a_key_is_a_word_not_an_error
    Dir.mktmpdir do |dir|
      Check.stub(:path, File.join(dir, "model_quota.json")) do
        Check.stub(:fetch_free_model_daily_requests, ->(_key) { flunk("no key must mean no GET") }) do
          Master::Io::KeyRotator.stub(:active_key_for, nil) do
            Master.stub(:models_config, {}) do
              assert_equal :no_key, Check.refresh_from_provider!
            end
          end
        end
      end
    end
  end
end
