# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"
require "json"
require "socket"

class TestCatalogCache < Minitest::Test
  CACHE = Master::CLI::Routing::ModelRouter::CatalogCache
  FakeConfig = Master::TestSupport::FakeConfig

  def teardown
    CACHE.instance_variable_set(:@path, nil)
    CACHE.instance_variable_set(:@snapshot, nil)
  end

  def test_ids_for_stores_and_returns_the_live_answer
    dir = Dir.mktmpdir
    CACHE.path = File.join(dir, "hosted_models.json")
    ids = CACHE.ids_for("https://x/v1", "keyless") { %w[a b] }

    assert_equal %w[a b], ids
    assert_equal %w[a b], CACHE.load_for("https://x/v1", "keyless")
    assert File.file?(CACHE.path)
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_ids_for_answers_the_cached_listing_when_the_fetch_fails
    dir = Dir.mktmpdir
    CACHE.path = File.join(dir, "hosted_models.json")
    CACHE.store("https://x/v1", "keyless", %w[a b])

    assert_equal %w[a b], CACHE.ids_for("https://x/v1", "keyless") { raise Errno::ECONNREFUSED }
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_ids_for_raises_through_when_nothing_is_cached
    dir = Dir.mktmpdir
    CACHE.path = File.join(dir, "hosted_models.json")
    error = assert_raises(RuntimeError) { CACHE.ids_for("https://x/v1", "keyless") { raise "down" } }

    assert_equal "down", error.message
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_store_never_records_an_empty_listing
    dir = Dir.mktmpdir
    CACHE.path = File.join(dir, "hosted_models.json")
    # An empty live answer is the failure shape the cache exists to paper
    # over, not a fact worth keeping.
    refute CACHE.store("https://x/v1", "keyless", [])
    assert_nil CACHE.load_for("https://x/v1", "keyless")
  ensure
    FileUtils.rm_rf(dir)
  end

  # An offline router rebuild answers the ids the endpoint listed the last
  # time it was reachable, instead of an empty hosted pool.
  def test_an_offline_rebuild_answers_the_cached_ids
    dir = Dir.mktmpdir
    server = nil
    thread = nil
    CACHE.path = File.join(dir, "hosted_models.json")
    rows = [{ "id" => "a", "model_type" => "chat" }, { "id" => "b", "model_type" => "chat" }]
    server = TCPServer.new("127.0.0.1", 0)
    body = JSON.generate("data" => rows)
    served = Queue.new
    thread = Thread.new do
      loop do
        socket = server.accept
        headers = []
        headers << socket.gets.to_s.strip until headers.last == ""
        socket.print("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        socket.close
        served << true
      end
    end
    ENV.delete("MASTER_NO_POOL_PROBES")
    spec = { "base" => "http://127.0.0.1:#{server.addr[1]}/v1", "key_env" => ["CACHE_TEST_KEY"],
             "keyless" => { "allow" => %w[a b] } }
    build = lambda do
      router = Master::CLI::Routing::ModelRouter.new(
        config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
      )
      router.instance_variable_get(:@rules)["openai_compatible"] = { "cacheable" => spec }
      router.define_singleton_method(:start_pool_probes) { {} }
      router
    end

    live = build.call
    assert_equal %w[cacheable:a cacheable:b], live.hosted_models
    served.pop
    server.close
    server = nil

    offline = build.call
    assert_equal %w[cacheable:a cacheable:b], offline.hosted_models
  ensure
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    ENV.delete("CACHE_TEST_KEY")
    thread&.kill
    server&.close
    FileUtils.rm_rf(dir)
  end
end
