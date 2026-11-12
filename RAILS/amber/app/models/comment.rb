# frozen_string_literal: true

class Comment < ApplicationRecord
  include Shared::CommentThreading

  belongs_to :user
  belongs_to :commentable, polymorphic: true

  validates :content, presence: true, length: { maximum: 2000 }

  after_commit :broadcast_post_comment

  private

  def broadcast_post_comment
    target = commentable
    return unless target.respond_to?(:broadcast_live_counts)

    target.broadcast_live_counts
    if destroyed?
      broadcast_remove_to target, target: ActionView::RecordIdentifier.dom_id(self)
    elsif previously_new_record?
      broadcast_append_to target,
        target: ActionView::RecordIdentifier.dom_id(target, "comments"),
        partial: "comments/comment", locals: { comment: self }
    elsif saved_change_to_content?
      broadcast_replace_to target,
        target: ActionView::RecordIdentifier.dom_id(self),
        partial: "comments/comment", locals: { comment: self }
    end
  end
end
