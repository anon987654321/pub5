# frozen_string_literal: true

class ComicStrip < ApplicationRecord
  include Shared::Reactable

  belongs_to :user

  STATUSES = %w[pending processing completed failed].freeze
  STYLES = %w[comic anime cartoon noir manga retro].freeze

  validates :prompt, presence: true, length: { maximum: 4_000 }
  validates :style, presence: true, inclusion: { in: STYLES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :newest_first, -> { order(created_at: :desc) }

  def safe_image_urls
    Array(image_urls).select { |url| ReplicateService.safe_output_url?(url) }
  end
end
