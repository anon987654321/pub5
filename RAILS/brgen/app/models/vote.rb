# frozen_string_literal: true

class Vote < ApplicationRecord
  tracks_activity created: "VoteCreated", source_vertical: "social", visibility: "private", actor: :user

  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :value, inclusion: { in: [ -1, 1 ] }
  validates :user_id, uniqueness: { scope: [ :votable_type, :votable_id ] }

  after_save    :rescore_author
  after_destroy :rescore_author
  after_save    :apply_score_delta
  after_destroy :apply_score_delta
  # Post counters are broadcast directly; touching Post would invalidate its card cache.
  after_commit :broadcast_votable_counts
  # Votes on comments still touch the comment itself, but no longer cascade into its post.
  after_commit :touch_non_post_votable

  private

  # Keep a votable's materialized score true, for the tables that have one.
  #
  # update_all rather than a reload-and-write: two people voting on the same post
  # in the same second must both count, and a read-modify-write loses one of
  # them. The database does the addition.
  #
  # The delta is the change this save made, not the value — an up-vote flipped to
  # a down-vote moves the score by -2, and saved_change_to_value gives both ends
  # of that without another query.
  def apply_score_delta
    klass = votable_type.to_s.safe_constantize
    return unless klass.respond_to?(:column_names) && klass.column_names.include?("score")

    delta =
      if destroyed?
        -value.to_i
      else
        before, after = saved_change_to_value
        after.to_i - before.to_i
      end
    return if delta.zero?

    klass.where(id: votable_id).update_all([ "score = COALESCE(score, 0) + ?", delta ])
  end

  # A post vote changes a reader-independent counter, not the post's content timestamp.
  def broadcast_votable_counts
    return unless votable_type == "Post"

    Post.unscoped.find_by(id: votable_id)&.broadcast_live_counts
  end

  # Preserve the prior touch semantics for other votable types (currently comments).
  # Post gets the targeted counter event above instead of a timestamp/cache invalidation.
  def touch_non_post_votable
    return if votable_type == "Post"

    klass = votable_type.to_s.safe_constantize
    klass.unscoped.find_by(id: votable_id)&.touch if klass.respond_to?(:unscoped)
  end

  # `votable.user` was a lazy belongs_to read on a votable the controller loaded
  # by id, and ApplicationRecord is strict_loading by default — so this raised
  # after the vote had already been written. It was invisible for as long as
  # VotesController#find_votable 404'd before ever reaching a save (post_vote_path
  # carries a slug, and find_votable called find). Fixing the 404 exposed it.
  #
  # votable is polymorphic, so Shared::StrictSafeAssociations#strict_safe does
  # not apply — it needs reflection.klass, which a polymorphic belongs_to has no
  # single answer for. Reading the author id off the table avoids instantiating
  # either record.
  def rescore_author
    klass = votable_type.to_s.safe_constantize
    return unless klass.respond_to?(:column_names) && klass.column_names.include?("user_id")

    author_id = klass.where(id: votable_id).pick(:user_id)
    author = User.find_by(id: author_id)
    ContentScore.new(user: author).call if author
  end
end
