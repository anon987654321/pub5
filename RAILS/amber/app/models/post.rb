# frozen_string_literal: true

class Post < ApplicationRecord
  include Shared::Commentable
  include Shared::Votable
  include Likeable

  belongs_to :user
  belongs_to :outfit, optional: true, touch: true
  belongs_to :item, optional: true, touch: true

  include Shared::RichTextLength
  include Shared::LinkEmbeddable
  embeds_links_from :body

  # body holds Tiptap's HTML. presence still works — the editor writes "" when
  # it is empty rather than "<p></p>" — but the limit has to measure the text,
  # or "<p>" and "</p>" spend seven of the writer's 500 characters.
  validates :body, presence: true
  validates_rich_text_length :body, maximum: 500

  scope :recent, -> { order(created_at: :desc) }
  scope :anonymous, -> { where(anonymous: true) }

  # Feed counts are projected once with the posts query, not read from the
  # comments association once per card. The composite commentable index serves
  # this correlated count, and the same target receives live Turbo updates.
  scope :with_feed_comment_count, lambda {
    count = Comment.unscoped.where(commentable_type: name)
                   .where("comments.commentable_id = posts.id")
                   .select("COUNT(*)")
    select("posts.*, (#{count.to_sql}) AS feed_comment_count")
  }
  scope :public_feed, -> { recent.with_feed_comment_count }

  # Shared::Commentable remains the fallback for individual records;
  # feed relations carry a correlated count projection to avoid N+1 reads.
  def comment_count
    has_attribute?(:feed_comment_count) ? self[:feed_comment_count].to_i : super
  end

  # Pay-per-view: a price makes the post gated; nil or zero keeps it free.
  def ppv? = price_minor.to_i.positive?

  # The access question the feed, the linktree and the controller all ask:
  # can this user read this post right now? The author needs no entitlement;
  # a free post belongs to the public feed; a gated post needs the unlock a
  # payment granted.
  def accessible_by?(user)
    return true unless ppv?
    return false if user.nil?

    user.id == user_id || user.entitled_to?(self)
  end

  def author_name
    return "anon" if anonymous? || user&.guest? || user&.deleted_at.present? || user&.deletion_scheduled_at.present?

    user.display_name
  end

  def anonymous?
    has_attribute?(:anonymous) && self[:anonymous]
  end

  after_commit :broadcast_live_refresh

  # Send only reader-independent counters across open feeds. The vote rail and
  # like button carry each reader's own pressed state, so a counter tick must
  # never replace either control for somebody else.
  def broadcast_live_counts(streams: nil)
    streams ||= ["posts", self]
    score, likes_count = self.class.unscoped.where(id:).pick(:score, :likes_count)
    comments_count = comments.count
    key = ActionView::RecordIdentifier.dom_id(self)
    content = [
      live_count_update(%([data-post-score="#{key}"]), score.to_i.to_s),
      live_count_update(%([data-post-like-count="#{key}"]), likes_count.to_i.to_s),
      live_count_update(
        %([data-post-comment-count="#{key}"]),
        comments_count.positive? ? comments_count.to_s : ""
      )
    ].join

    streams.each do |stream|
      Turbo::StreamsChannel.broadcast_stream_to(stream, content:)
    end
  rescue StandardError => e
    Rails.logger.warn("amber_post_live_counts #{id}: #{e.class}: #{e.message}")
  end

  def to_markdown
    body.to_s
  end

  private

  # Only explicit Vote and Comment callbacks use the counter stream. A bare
  # Post touch has no reliable interaction context, so it retains the full
  # refresh path rather than guessing that an arbitrary update changed a count.
  def broadcast_live_refresh
    broadcast_refresh_to "posts"
    broadcast_refresh_to self
  end

  def live_count_update(targets, value)
    Turbo::StreamsChannel.turbo_stream_action_tag(:update, targets:, template: value.to_s)
  end
end
