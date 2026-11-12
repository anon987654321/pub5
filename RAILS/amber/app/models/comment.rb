# frozen_string_literal: true

class Comment < ApplicationRecord
  include Shared::CommentThreading

  belongs_to :user
  belongs_to :commentable, polymorphic: true

  validates :content, presence: true, length: { maximum: 2000 }

  after_commit :broadcast_post_comment

  private

  def broadcast_post_comment
    return unless commentable_type == "Post"

    target = Post.find_by(id: commentable_id)
    return unless target

    # Feed readers need only the new count. Readers on the detail page need
    # the complete thread, whose controls are rendered for each viewer; refresh
    # that narrower stream rather than broadcasting one reader's comment UI.
    target.broadcast_live_counts(streams: ["posts"])
    target.broadcast_refresh_to target
  end
end
