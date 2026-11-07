# frozen_string_literal: true

module Shared
  class S2sConversion < ApplicationRecord
    self.table_name = "s2s_conversions"
    belongs_to :user, class_name: "::User"
    validates :reference, presence: true, length: { maximum: 200 }
    validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :status, inclusion: { in: %w[queued sent partial failed] }
  end
end
