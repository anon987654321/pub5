# frozen_string_literal: true

module Shared
  class ReferralCredit < ApplicationRecord
    self.table_name = "referral_credits"
    belongs_to :user, class_name: "::User"
    belongs_to :referral_splinter, class_name: "Shared::ReferralSplinter"
    scope :active, -> { where(expires_at: Time.current..) }
  end
end
