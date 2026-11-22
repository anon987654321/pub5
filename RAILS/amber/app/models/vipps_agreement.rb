# frozen_string_literal: true

# A Vipps Recurring agreement: the Norwegian rail's answer to a monthly
# subscription. The agreement is a payment method on the entitlement it
# carries, not a second subscription primitive - while it is ACTIVE and each
# charge succeeds, the user holds entitlement_name; a STOPPED agreement stops
# extending it.
class VippsAgreement < ApplicationRecord
  STATUSES = %w[PENDING ACTIVE STOPPED EXPIRED].freeze

  belongs_to :user

  validates :agreement_id, presence: true, uniqueness: true
  validates :state, inclusion: { in: STATUSES }
  validates :entitlement_name, presence: true
  validates :amount_minor, numericality: { greater_than: 0 }

  scope :active, -> { where(state: "ACTIVE") }

  def active? = state == "ACTIVE"
end
