# frozen_string_literal: true

require "test_helper"

class CommerceLedgerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email_address: "ledger-user-#{SecureRandom.hex(4)}@example.test",
      password: "password123"
    )
    @actor = User.create!(
      email_address: "ledger-actor-#{SecureRandom.hex(4)}@example.test",
      password: "password123"
    )
  end

  def record(key: "test:credit:one", entitlement: "playlist_pro", **overrides)
    attributes = {
      idempotency_key: key,
      entry_type: "credit_granted",
      user_id: @user.id,
      actor_id: @actor.id,
      entitlement:,
      expires_at: (@ledger_expiry ||= 30.days.from_now.change(usec: 0)),
      metadata: { vertical: "playlist" },
    }.merge(overrides)

    Shared::Commerce::Ledger.record!(**attributes)
  end

  test "a repeated idempotency key returns the original journal row" do
    first = record
    second = record

    assert_equal first.id, second.id
    assert_equal 1, Shared::CommerceLedgerEntry.where(idempotency_key: "test:credit:one").count
  end

  test "an idempotency key cannot be reused for different facts" do
    record

    error = assert_raises(Shared::Commerce::Ledger::IdempotencyConflict) do
      record(entitlement: "dating_pro")
    end

    assert_includes error.message, "entitlement"
    assert_equal 1, Shared::CommerceLedgerEntry.where(idempotency_key: "test:credit:one").count
  end

  test "a ledger entry cannot be updated or destroyed" do
    entry = record

    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(entitlement: "dating_pro") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.destroy! }
    assert_equal "playlist_pro", entry.reload.entitlement
  end

  test "amount and currency are an inseparable nonnegative pair" do
    assert_raises(ArgumentError) do
      record(key: "test:amount:missing-currency", amount_minor: 1200)
    end

    assert_raises(ArgumentError) do
      record(key: "test:amount:missing-amount", currency: "NOK")
    end

    assert_raises(ArgumentError) do
      record(key: "test:amount:negative", amount_minor: -1, currency: "NOK")
    end

    entry = record(key: "test:amount:valid", amount_minor: 1200, currency: "nok")
    assert_equal 1200, entry.amount_minor
    assert_equal "NOK", entry.currency
  end

  test "ledger metadata is limited to the vertical contract" do
    assert_raises(ArgumentError) do
      record(key: "test:metadata:unknown", metadata: { email: @user.email_address })
    end
  end
end
