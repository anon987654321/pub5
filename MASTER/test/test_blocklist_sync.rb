# frozen_string_literal: true

require_relative "test_helper"

class TestBlocklistSync < Minitest::Test
  class FakeClient
    def initialize(ok: true)
      @ok = ok
    end

    def post(_path, body:)
      @body = body
      @ok ? Master::Result.ok(:created) : Master::Result.err("offline", category: :infrastructure)
    end

    attr_reader :body
  end

  def setup
    @dir = Dir.mktmpdir("blocklist-sync")
    @web = FakeClient.new
    @mobile = FakeClient.new(ok: false)
    @now = Time.utc(2026, 11, 12, 12)
    @service = Master::Ground::BlocklistSync.new(
      rails_clients: { web: @web, mobile: @mobile }, root: @dir,
      authorize: ->(**) { true }, clock: -> { @now },
    )
  end

  def teardown
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  def test_refuses_mutations_without_explicit_authorization
    service = Master::Ground::BlocklistSync.new(
      rails_clients: { web: @web }, root: @dir,
    )
    result = service.block(target_id: "42", reason: "abuse", platforms: ["web"])
    assert result.err?
    assert_equal :policy, result.category
  end

  def test_partial_sync_only_claims_successful_platform
    result = @service.block(target_id: "42", reason: "report reviewed", platforms: %w[web mobile])
    assert result.err?
    assert @service.blocked?(target_id: "42", platform: "web")
    refute @service.blocked?(target_id: "42", platform: "mobile")
  end

  def test_temporary_block_requires_a_bounded_ttl
    result = @service.block(target_id: "43", reason: "review", platforms: ["web"], permanent: false)
    assert result.err?
    assert_equal :validation, result.category
  end

  def test_unknown_platform_is_rejected_before_remote_write
    result = @service.block(target_id: "44", reason: "review", platforms: ["unknown"])
    assert result.err?
    assert_equal :validation, result.category
    assert_nil @web.body
  end

  def test_temporary_block_expires_locally
    result = @service.block(
      target_id: "47", reason: "temporary review", platforms: ["web"],
      permanent: false, ttl_s: 60,
    )
    assert result.ok?
    assert @service.blocked?(target_id: "47", platform: "web")
    @now += 61
    @service.instance_variable_set(:@clock, -> { @now })
    refute @service.blocked?(target_id: "47", platform: "web")
  end

  def test_unblock_without_a_verified_adapter_keeps_remote_block_record
    @web.define_singleton_method(:post) { |_path, body:| Master::Result.ok(body) }
    @service.block(target_id: "45", reason: "review", platforms: ["web"])
    result = @service.unblock(target_id: "45")
    assert result.err?
    assert_equal :policy, result.category
    assert @service.blocked?(target_id: "45", platform: "web")
  end

  def test_unblock_removes_record_only_after_remote_confirmation
    @web.define_singleton_method(:post) { |_path, body:| Master::Result.ok(body) }
    service = Master::Ground::BlocklistSync.new(
      rails_clients: { web: @web }, root: @dir, authorize: ->(**) { true },
      unblocker: ->(**) { Master::Result.ok(:removed) },
    )
    service.block(target_id: "46", reason: "review", platforms: ["web"])
    result = service.unblock(target_id: "46")
    assert result.ok?
    assert_equal "CONFIRMED", result.value![:remote_sync]
    refute service.blocked?(target_id: "46", platform: "web")
  end
end
