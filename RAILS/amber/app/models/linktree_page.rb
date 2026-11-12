# frozen_string_literal: true

# A creator's public link-in-bio page. Unauthenticated by design: the page is
# the top of the funnel, and every internal link on it lands behind the normal
# access checks. The page belongs to the CreatorProfile, not to a second user
# type.
class LinktreePage < ApplicationRecord
  belongs_to :creator_profile
  has_many :linktree_links, -> { order(:position) }, dependent: :destroy
  has_many :linktree_events, dependent: :destroy

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9\-_]+\z/ }

  def to_param = slug
end
