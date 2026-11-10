# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"
require "json"
require "socket"

class TestPrivacyPosture < Minitest::Test
  POSTURE = Master::CLI::Routing::ModelRouter::PrivacyPosture
  FakeConfig = Master::TestSupport::FakeConfig

  def test_parse_maps_declared_postures_and_defaults_to_unknown
    assert_equal :anonymous, POSTURE.parse("anonymous")
    assert_equal :logs_prompts, POSTURE.parse("logs_prompts")
    assert_equal :trains_on_data, POSTURE.parse("trains_on_data")
    assert_equal :unknown, POSTURE.parse("trust_me")
    assert_equal :unknown, POSTURE.parse(nil)
  end

  def test_only_anonymous_may_carry_sensitive_dispatch
    refute POSTURE.allows?(:unknown, :sensitive)
    refute POSTURE.allows?(:logs_prompts, :sensitive)
    refute POSTURE.allows?(:trains_on_data, :sensitive)
    assert POSTURE.allows?(:anonymous, :sensitive)
  end

  def test_normal_sensitivity_rides_any_posture
    %i[anonymous logs_prompts trains_on_data unknown].each do |posture|
      assert POSTURE.allows?(posture, :normal), posture
    end
  end

  # The endpoint index carries the lane's declared posture; an id no endpoint
  # lists answers unknown.
  def test_hosted_posture_answers_the_declared_or_unknown
    dir = Dir.mktmpdir
    server = nil
    thread = nil
    Master::CLI::Routing::ModelRouter::CatalogCache.path = File.join(dir, "hosted_models.json")
    rows = [{ "name" => "openai-fast", "tier" => "anonymous" }]
    server = TCPServer.new("127.0.0.1", 0)
    body = JSON.generate(rows)
    thread = Thread.new do
      socket = server.accept
      headers = []
      headers << socket.gets.to_s.strip until headers.last == ""
      socket.print("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end
    ENV.delete("MASTER_NO_POOL_PROBES")
    spec = { "base" => "http://127.0.0.1:#{server.addr[1]}/openai", "key_env" => ["POSTURE_TEST_KEY"],
             "privacy_posture" => "logs_prompts", "keyless" => { "tier" => "anonymous" } }
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.instance_variable_get(:@rules)["openai_compatible"] = { "postured" => spec }
    router.define_singleton_method(:start_pool_probes) { {} }

    assert_equal :logs_prompts, router.hosted_posture_for("postured:openai-fast")
    assert_equal :unknown, router.hosted_posture_for("nowhere:nothing")
  ensure
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    ENV.delete("POSTURE_TEST_KEY")
    thread&.kill
    server&.close
    FileUtils.rm_rf(dir)
  end

  def test_the_dispatch_guard_refuses_unknown_and_allows_anonymous
    guard = Object.new.extend(Master::Review::LLMDispatcher::HttpSender)
    assert guard.send(:refuses_sensitive?, { posture: :unknown }, :sensitive)
    assert guard.send(:refuses_sensitive?, {}, :sensitive)
    refute guard.send(:refuses_sensitive?, { posture: :anonymous }, :sensitive)
    refute guard.send(:refuses_sensitive?, { posture: :logs_prompts }, :normal)
  end
end
