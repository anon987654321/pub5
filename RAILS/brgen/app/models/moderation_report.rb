# frozen_string_literal: true

class ModerationReport < ApplicationRecord
  belongs_to :user
  belongs_to :reportable, polymorphic: true

  REASONS = %w[spam scam abuse unsafe illegal copyright duplicate other].freeze
  # These are the public report controls' real targets. A signed GlobalID proves
  # integrity, not that a model is safe to expose to the moderation workflow.
  REPORTABLE_TYPES = %w[Post Comment Message User Tv::Video Playlist::Track].freeze
  STATUSES = %w[open reviewing resolved dismissed].freeze
# What the report picker offers; a caller's own default joins them.
PICKER_REASONS = %w[spam abuse illegal other].freeze
DETAILS_LIMIT = 1_000

def self.picker_reasons(chosen) = (PICKER_REASONS + [ chosen ]).uniq & REASONS

  validates :reason, inclusion: { in: REASONS }
  validates :status, inclusion: { in: STATUSES }
  validates :reportable_type, inclusion: { in: REPORTABLE_TYPES }

  def self.reportable?(record)
    record && REPORTABLE_TYPES.include?(record.class.base_class.name)
  end

  scope :open, -> { where(status: "open") }
  scope :recent, -> { order(created_at: :desc) }
end
