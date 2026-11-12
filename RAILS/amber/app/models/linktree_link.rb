# frozen_string_literal: true

# One link on a LinktreePage. A link points outward (url) or inward
# (linkable: a Post, a LiveStream) - an inward link routes through the gated
# surface's own checks, so the page never weakens the paywall.
class LinktreeLink < ApplicationRecord
  belongs_to :linktree_page
  belongs_to :linkable, polymorphic: true, optional: true
  has_many :linktree_events, dependent: :destroy

  validates :title, presence: true, length: { maximum: 120 }
  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, if: -> { url.present? }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :visible, -> { where(visible: true) }

  # The destination the click routes to: an internal path for a linkable, the
  # stored URL otherwise. A row with neither is data-entry error, not a route.
  def destination_path
    return url.to_s if url.present?
    return unless linkable

    case linkable
    when Post then Rails.application.routes.url_helpers.post_path(linkable)
    when LiveStream then Rails.application.routes.url_helpers.live_stream_path(linkable)
    end
  end

  def internal? = url.blank? && linkable.present?
end
