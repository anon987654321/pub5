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
  scope :public_feed, -> { recent }

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
  def broadcast_live_counts
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

    ["posts", self].each do |stream|
      Turbo::StreamsChannel.broadcast_stream_to(stream, content:)
    end
  rescue StandardError => e
    Rails.logger.warn("amber_post_live_counts #{id}: #{e.class}: #{e.message}")
  end

  def to_markdown
    body.to_s
  end

  private

  # Vote, comment and counter writes touch the post. Re-rendering the whole
  # feed on those writes interrupts reading and redraws viewer-specific state;
  # send the counters instead. Content/visibility changes still refresh the
  # page so every reader sees the new card. Creates and deletes also retain the
  # established refresh behaviour until Amber has a staged-arrival surface.
  TOUCH_ONLY_COLUMNS = %w[updated_at lock_version].freeze

  def broadcast_live_refresh
    changed = saved_changes.keys.map(&:to_s)
    touch_only = changed.any? && (changed - TOUCH_ONLY_COLUMNS).empty?
    if !destroyed? && !previously_new_record? && touch_only
      broadcast_live_counts
      return
    end

    broadcast_refresh_to "posts"
    broadcast_refresh_to self
  end

  def live_count_update(targets, value)
    Turbo::StreamsChannel.turbo_stream_action_tag(:update, targets:, template: value.to_s)
  end
end
