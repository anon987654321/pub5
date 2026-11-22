# frozen_string_literal: true

# The money fact behind an entitlement, whichever rail carried it: Stripe for
# Amber Premium, Vipps for one-off unlocks and Norwegian recurring agreements.
# state tracks the rail's own lifecycle; a captured row is the receipt a
# refund or an audit asks about.
class PaymentTransaction < ApplicationRecord
  RAILS = %w[stripe vipps].freeze
  STATES = %w[pending authorized captured failed refunded].freeze

  belongs_to :user
  belongs_to :purchasable, polymorphic: true, optional: true

  validates :rail, inclusion: { in: RAILS }
  validates :state, inclusion: { in: STATES }
  validates :reference, presence: true
  validates :amount_minor, numericality: { greater_than_or_equal_to: 0 }

  scope :captured, -> { where(state: "captured") }
end
