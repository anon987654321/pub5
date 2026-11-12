# frozen_string_literal: true

class CreatorProfile < ApplicationRecord
  include Shared::RichTextLength

  belongs_to :user
  has_many :creator_wardrobe_items, dependent: :destroy
  has_many :items, through: :creator_wardrobe_items
  # The link-in-bio page is the profile's public face; it cannot outlive the
  # profile without 500ing the profile's destroy (foreign_key_dependency_test).
  has_one :linktree_page, dependent: :destroy

  validates :handle, presence: true, uniqueness: true, format: { with: /\A[a-zA-Z0-9_\.\-]+\z/ }
  validates :display_name, presence: true, length: { maximum: 80 }
  # bio holds Tiptap's HTML; the maximum measures the text inside it.
  validates_rich_text_length :bio, maximum: 1_000

  normalizes :handle, with: ->(value) { value.to_s.strip.downcase }

  scope :publicly_visible, -> { where(public: true).joins(:user).where(users: { deleted_at: nil, deletion_scheduled_at: nil }) }
end
