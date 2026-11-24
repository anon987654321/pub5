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
    monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000
    assert_in_delta 6 * 3600 * 1000, long - monotonic_now, 5000
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
    refute cache.filter(%w[m1 m2]).include?("m1")
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

  def test_router_failover_categories_are_parked_across_turns
    cache = Master::Io::ModelSkipCache
    ENV["MASTER_FALLBACK_SKIP_TTL_MS"] = "600000"
    travel_to(1_000_000)

    expected = {
      offline: cache.transient_skip_ttl_ms,
      budget: cache.skip_ttl_ms,
      invalid_request: cache.skip_ttl_ms,
    }
    expected.each do |category, duration|
      model = "model-#{category}"
      cache.skip!(model, reason: "failure without a provider reset time", category:)

      assert_equal 1_000_000 + duration, cache.skipped_until_ms(model), category.to_s
      refute cache.filter([model]).include?(model), category.to_s
    end
  ensure
    cache.clock = nil
  end

  CLEF = "400 Bad Request: clef:27b is a decision model, only supports /v1/systemone"

  # ollama_cloud:clef:27b (2026-11-23) refused chat for good. A stated
  # incapability parks that one model for hours; a bare 400 never does, because
  # a 400 can be an oversized prompt that a healthy model would answer shortened.
  def test_a_stated_incapability_is_recognised_and_ordinary_400s_are_not
    reply = Master::Io::LaneReply
    assert reply.incapable?(CLEF)
    assert reply.incapable?("model rerank-v3 is an embedding model and only supports /v1/embeddings")
    refute reply.incapable?("400 Bad Request: prompt is too long for this model")
    refute reply.incapable?("400 invalid request body")
    assert_nil reply.read(CLEF), "must not become a lane verdict: verdicts retire whole lanes"
  end

  def test_for_ms_parks_one_model_for_the_stated_time_and_not_its_siblings
    cache = Master::Io::ModelSkipCache
    cache.clock = -> { 1_000 }
    cache.skip!("ollama_cloud:clef:27b", reason: CLEF, category: :invalid_request,
                for_ms: cache::INCAPABLE_PARK_MS)

    assert_equal 1_000 + cache::INCAPABLE_PARK_MS, cache.skipped_until_ms("ollama_cloud:clef:27b")
    assert cache.skipped?("ollama_cloud:clef:27b")
    refute cache.skipped?("ollama_cloud:gemma3:27b")
  ensure
    cache.clock = nil
  end

  def test_without_for_ms_an_invalid_request_keeps_the_ordinary_park
    cache = Master::Io::ModelSkipCache
    cache.clock = -> { 1_000 }
    cache.skip!("m1", reason: "400 prompt too long", category: :invalid_request)
    assert_equal 1_000 + 5000, cache.skipped_until_ms("m1")
  ensure
    cache.clock = nil
  end
end
