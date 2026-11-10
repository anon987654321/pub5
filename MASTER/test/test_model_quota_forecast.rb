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
        Check.stub(:free_model_request_count, 100) do
          Check.stub(:free_model_burn_rate_per_day, 200.0) do
            forecast = Check.forecast("demo:free", now:)
            assert_equal 100, forecast[:used]
            assert_equal 100, forecast[:remaining]
            assert_in_delta 200, forecast[:projected_daily], 0.01
            assert_in_delta 12, forecast[:exhaustion_hours], 0.01
          end
        end
      end
    end
  end

  def test_burn_risk_turns_on_before_hard_exhaustion
    now = Time.utc(2026, 9, 28, 20, 0, 0)

    Check.stub(:trackable?, true) do
      Check.stub(:daily_limit, 200) do
        Check.stub(:free_model_request_count, 135) do
          Check.stub(:free_model_burn_rate_per_day, 405.0) do
            assert Check.burn_risk?("demo:free", now:)
          end
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
          Check.stub(:fetch_free_model_daily_requests, { "used" => 12, "limit" => 50, "remaining" => 7 }) do
            assert_equal :refreshed, Check.refresh_from_provider!(now:, day: "2026-11-08")
          end
        end

        Check.stub(:trackable?, true) do
          Check.stub(:count, 3) do
            Check.stub(:daily_limit, 50) do
              assert_equal 7, Check.remaining("demo:free", day: "2026-11-08", now:)
              provider_forecast = Check.forecast("demo:free", now:)
              assert_equal 7, provider_forecast[:remaining]
              assert_equal 50, provider_forecast[:limit]
              assert_equal 12, provider_forecast[:used]
              assert_equal "provider", provider_forecast[:remaining_source]
              refute Check.over_quota?("demo:free", day: "2026-11-08", now:)

              Check.stub(:active_openrouter_key, "test-key") do
                Check.stub(:fetch_free_model_daily_requests, { "used" => 50, "limit" => 50, "remaining" => 0 }) do
                  assert_equal :refreshed, Check.refresh_from_provider!(now: now + 3600, day: "2026-11-08")
                end
              end
              assert Check.over_quota?("demo:free", day: "2026-11-08", now: now + 3600), "the provider says nothing is left"
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
          Check.stub(:free_model_request_count, 10) do
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
          Check.stub(:fetch_free_model_daily_requests, { "used" => 12, "limit" => 50, "remaining" => 7 }) { Check.refresh_from_provider!(now:, day: "2026-11-08") }
        end

        Check.stub(:trackable?, true) do
          assert_equal 7, Check.remaining("demo:free", day: "2026-11-08", now:)
          assert_nil Check.provider_remaining("demo:free", day: "2026-11-09", now:), "yesterday's reading is not today's"
        end
      end
    end
  end

  def test_normalize_provider_reading_accepts_the_documented_object
    reading = Check.normalize_provider_reading(
      "used" => 12, "limit" => 50, "remaining" => 38,
    )

    assert_equal({ "used" => 12, "limit" => 50, "remaining" => 38 }, reading)
    assert_nil Check.normalize_provider_reading(38), "a scalar is not the documented response shape"
    assert_nil Check.normalize_provider_reading("used" => 12, "limit" => 50)
  end

  def test_stale_provider_reading_is_visible_but_not_used_for_routing
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 11, 8, 10, 0, 0)
      Check.stub(:path, File.join(dir, "model_quota.json")) do
        Check.stub(:free_model_request_count, 10) do
          Check.stub(:active_openrouter_key, "test-key") do
            Check.stub(:fetch_free_model_daily_requests, { "used" => 10, "limit" => 50, "remaining" => 40 }) do
              assert_equal :refreshed, Check.refresh_from_provider!(now:, day: "2026-11-08")
            end
          end

          Check.stub(:trackable?, true) do
            Check.stub(:daily_limit, 50) do
              Check.stub(:free_model_burn_rate_per_day, 20.0) do
                stale_at = now + Check::PROVIDER_REFRESH_TTL_S + 1
                assert_equal 40, Check.remaining("demo:free", day: "2026-11-08", now: stale_at)
                forecast = Check.forecast("demo:free", day: "2026-11-08", now: stale_at)
                assert_equal "burn_forecast", forecast[:remaining_source]
                provider = Check.provider_quota_snapshot(day: "2026-11-08", now: stale_at)
                assert_equal false, provider[:fresh]
                assert_equal "stale_provider", provider[:source]
              end
            end
          end
        end
      end
    end
  end

  def test_provider_sample_is_adjusted_for_local_calls_after_the_sample
    Dir.mktmpdir do |dir|
      now = Time.now.utc
      Check.stub(:path, File.join(dir, "model_quota.json")) do
        Check.stub(:active_openrouter_key, "test-key") do
          Check.stub(:fetch_free_model_daily_requests, { "used" => 12, "limit" => 50, "remaining" => 38 }) do
            Check.record("demo:free")
            Check.record("demo:free")
          end
        end

        sample = Check.provider_quota_snapshot(now:)
        assert_equal 1, sample[:local_requests_since_read]
        assert_equal 37, Check.remaining("demo:free", now:)
        forecast = Check.forecast("demo:free", now:)
        assert_equal 13, forecast[:used]
        assert_equal 50, forecast[:limit]
        assert_equal 37, forecast[:remaining]
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
