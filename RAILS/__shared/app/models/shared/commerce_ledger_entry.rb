# frozen_string_literal: true

module Shared
  # Immutable journal row for a credit or entitlement event. The ledger records
  # what the domain granted; it does not move money or replace the live
  # entitlement readers in this first slice.
  class CommerceLedgerEntry < ApplicationRecord
    self.table_name = "commerce_ledger_entries"

    ENTRY_TYPES = %w[
      credit_granted
      credit_consumed
      entitlement_granted
      entitlement_revoked
    ].freeze

    belongs_to :user, class_name: "::User"
    belongs_to :actor, class_name: "::User", optional: true
    belongs_to :source, polymorphic: true, optional: true

    validates :entry_type, inclusion: { in: ENTRY_TYPES }
    # The unique database index arbitrates concurrent insertions. A model-level
    # uniqueness query rejects a legitimate create_or_find_by! replay before the
    # insert can reach that constraint.
    validates :idempotency_key, presence: true, length: { maximum: 160 }
    validates :entitlement, presence: true, length: { maximum: 64 }
    validates :amount_minor,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 },
              allow_nil: true
    validates :currency, format: { with: /\A[A-Z]{3}\z/ }, allow_nil: true
    validates :expires_at, presence: true, if: -> { entry_type == "credit_granted" }
    validate :amount_and_currency_are_paired

    before_update :refuse_mutation!
    before_destroy :refuse_mutation!

    def readonly?
      persisted? || super
    end

    private

    def amount_and_currency_are_paired
      return if amount_minor.nil? == currency.nil?

      errors.add(amount_minor.nil? ? :amount_minor : :currency, :blank)
    end

    def refuse_mutation!
      raise ActiveRecord::ReadOnlyRecord, "commerce ledger entries are append-only"
    end
  end
end
