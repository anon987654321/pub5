# frozen_string_literal: true

# One Vipps ePayment charge. state mirrors Vipps' own vocabulary (CREATED,
# AUTHORIZED, CAPTURED, ABORTED, EXPIRED, TERMINATED, CANCELLED, REFUNDED) so
# the polling job copies the API's answer straight in - no second vocabulary
# to translate. The purchasable says what the charge was for; capturing it
# grants the entitlement the purchasable promises.
class VippsPayment < ApplicationRecord
  TERMINAL_CAPTURED = "CAPTURED"
  TERMINAL_FAILED = %w[ABORTED EXPIRED TERMINATED CANCELLED].freeze
  STATUSES = %w[CREATED AUTHORIZED CAPTURED ABORTED EXPIRED TERMINATED CANCELLED REFUNDED].freeze

  belongs_to :user
  belongs_to :purchasable, polymorphic: true, optional: true

  validates :reference, presence: true, uniqueness: true
  validates :state, inclusion: { in: STATUSES }
  validates :amount_minor, numericality: { greater_than: 0 }
  validates :idempotency_key, presence: true

  scope :pending, -> { where(state: %w[CREATED AUTHORIZED]) }

  def captured? = state == TERMINAL_CAPTURED
  def failed? = TERMINAL_FAILED.include?(state)
  def settled? = captured? || failed? || state == "REFUNDED"
end
