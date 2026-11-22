# frozen_string_literal: true

require_relative "test_helper"

class TestNotificationAggregator < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("notifications")
    @now = Time.utc(2026, 11, 12, 12)
    @allowed = true
    @inbox = Master::Ground::NotificationAggregator.new(
      root: @dir, permission_check: -> { @allowed }, clock: -> { @now },
    )
  end

  def teardown
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  def test_default_permission_denies_storage
    inbox = Master::Ground::NotificationAggregator.new(root: @dir, permission_check: -> { false })
    result = inbox.record(platform: "web", kind: "message", text: "hello")
    assert result.err?
    assert_equal :policy, result.category
  end

  def test_records_and_returns_unread_notifications_by_priority
    low = @inbox.record(platform: "web", kind: "system", text: "FYI").value!
    high = @inbox.record(platform: "mobile", kind: "alert", text: "Emergency").value!
    result = @inbox.pending
    assert result.ok?
    assert_equal 2, result.value![:total]
    assert_equal high["id"], result.value![:rows].first["id"]
    assert_equal low["id"], result.value![:rows].last["id"]
  end

  def test_mark_read_removes_item_from_pending
    row = @inbox.record(platform: "web", kind: "message", text: "Hello").value!
    assert @inbox.mark_read(id: row["id"]).ok?
    assert_equal 0, @inbox.pending.value![:total]
  end

  def test_snoozed_notification_returns_after_deadline
    row = @inbox.record(platform: "web", kind: "message", text: "Later").value!
    assert @inbox.snooze(id: row["id"], hours: 1).ok?
    assert_equal 0, @inbox.pending.value![:total]
    @now += 3_601
    assert_equal 1, @inbox.pending.value![:total]
  end

  def test_invalid_pending_limit_is_refused
    assert @inbox.pending(limit: 0).err?
    assert @inbox.pending(limit: 201).err?
  end
end
