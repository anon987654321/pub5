# frozen_string_literal: true

require_relative "test_helper"

class TestModelSkipCache < Minitest::Test
  def setup
    Master::Io::ModelSkipCache.clear!
    @prev = ENV["MASTER_FALLBACK_SKIP_TTL_MS"]
    ENV["MASTER_FALLBACK_SKIP_TTL_MS"] = "5000"
  end

  def teardown
    ENV["MASTER_FALLBACK_SKIP_TTL_MS"] = @prev
    Master::Io::ModelSkipCache.clear!
  end

  def test_default_clock_uses_monotonic_time_but_reset_parser_uses_realtime
    cache = Master::Io::ModelSkipCache
    cache.clock = nil
    monotonic = 12_345.678
    realtime = 1_800_000_000.0
    parsed_times = []
    clock = lambda do |kind, *_args|
      kind == Process::CLOCK_MONOTONIC ? monotonic : realtime
    end

    Master::Io::LaneReply.stub(:stated_wait, ->(_reason, now) { parsed_times << now; nil }) do
      Master::Io::LaneReply.stub(:daily_reset, ->(_reason, now) { parsed_times << now; nil }) do
        Process.stub(:clock_gettime, clock) do
          assert_equal (monotonic * 1000).round, cache.now_ms
          cache.skip!("m1", reason: "temporary failure", category: :failure)
        end
      end
    end

    assert_equal [realtime, realtime], parsed_times
    assert_equal (monotonic * 1000).round + cache.transient_skip_ttl_ms,
      cache.skipped_until_ms("m1")
  ensure
    cache.clock = nil
    cache.clear!
  end

  def test_skip_and_filter
    Master::Io::ModelSkipCache.skip!("m1", reason: "rate limit", category: :rate_limit)
    assert Master::Io::ModelSkipCache.skipped?("m1")
    filtered = Master::Io::ModelSkipCache.filter(%w[m1 m2])
    assert_equal %w[m2], filtered
  end

  def test_a_stated_wait_sets_the_park_and_a_shorter_one_never_shortens_it
    cache = Master::Io::ModelSkipCache
    cache.skip!("m1", reason: "429 Too Many Requests, retry after 6h", category: :rate_limit)
    long = cache.skipped_until_ms("m1")
    cache.skip!("m1", reason: "provider overloaded", category: :provider_error)

    assert_equal long, cache.skipped_until_ms("m1")
    assert_in_delta 6 * 3600 * 1000, long - (Time.now.to_f * 1000), 5000
  end

  def test_a_rate_limit_without_a_stated_wait_parks_briefly
    travel_to(0)
    Master::Io::ModelSkipCache.skip!("m1", reason: "429", category: :rate_limit)

    assert_equal Master::Io::ModelSkipCache.transient_skip_ttl_ms, Master::Io::ModelSkipCache.skipped_until_ms("m1")
  ensure
    Master::Io::ModelSkipCache.clock = nil
  end

  # A refusal that names no category (the dispatcher's failure_status maps one
  # to :failure) parks a model like any other transient fault; leaving it
  # unparked re-asked the same dead lane on every call of a run.
  def test_an_unnamed_failure_parks_briefly_too
    travel_to(0)
    cache = Master::Io::ModelSkipCache
    cache.skip!("m1", reason: "something went wrong", category: :failure)

    assert_equal cache.transient_skip_ttl_ms, cache.skipped_until_ms("m1")
    refute cache.filter(["m1", "m2"]).include?("m1")
  ensure
    Master::Io::ModelSkipCache.clock = nil
  end

  def travel_to(epoch_ms)
    @now = epoch_ms
    Master::Io::ModelSkipCache.clock = -> { @now }
  end

  def test_untimed_failures_escalate_and_a_success_resets_them
    cache = Master::Io::ModelSkipCache
    ENV["MASTER_FALLBACK_SKIP_TTL_MS"] = "600000"

    travel_to(1_000_000)
    parks = 4.times.map do
      cache.skip!("m1", reason: "upstream overloaded", category: :provider_error)
      span = cache.skipped_until_ms("m1") - @now
      travel_to(cache.skipped_until_ms("m1"))
      span
    end

    assert_equal [cache.transient_skip_ttl_ms, 60_000, 300_000, 300_000], parks
    cache.succeeded!("m1")
    cache.skip!("m1", reason: "upstream overloaded", category: :provider_error)
    assert_equal cache.transient_skip_ttl_ms, cache.skipped_until_ms("m1") - @now
  ensure
    cache.clock = nil
  end

  def test_a_long_park_lets_one_call_through_near_its_end
    cache = Master::Io::ModelSkipCache
    travel_to(0)
    cache.skip!("m1", reason: "retry after 10m", category: :rate_limit)

    # Well before the end, two minutes out (a slot opens), 10s into the short
    # slot, and thirty seconds after it opened (the next slot).
    parked = [0, 500_000, 510_000, 535_000].map do |moment|
      travel_to(moment)
      cache.skipped?("m1")
    end

    assert_equal [true, false, true, false], parked
  ensure
    cache.clock = nil
  end

  def test_skip_ttl_from_env
    assert_equal 5000, Master::Io::ModelSkipCache.skip_ttl_ms
  end
end
