# frozen_string_literal: true

module Shared
  class ReferralCredit < ApplicationRecord
    self.table_name = "referral_credits"
    belongs_to :user, class_name: "::User"
    belongs_to :referral_splinter, class_name: "Shared::ReferralSplinter"

    # Journal the grant in the same database transaction. If the ledger write
    # fails, the credit must not survive without its audit event.
    after_create :record_commerce_ledger_entry

    scope :active, -> { where(expires_at: Time.current..) }

    private

    def record_commerce_ledger_entry
      Shared::Commerce::Ledger.record_credit!(self)
    end
  end
end
