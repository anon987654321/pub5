# frozen_string_literal: true

# likes_count counts people, not presses: the unique reactions index refuses a
# second like from the same person, and only a new one moves the counter.
module Likeable
  extend ActiveSupport::Concern

  # delete_all, not destroy: no reaction callback needs to run, and nothing has to load.
  included do
    has_many :likes, -> { where(kind: "like") }, class_name: "Reaction", as: :reactable,
                inverse_of: :reactable, dependent: :delete_all
  end

  # True when this was the person's first like. The exists? guard answers the
  # ordinary duplicate before Reaction's own user-uniqueness validation can
  # raise; a simultaneous double-press still hits the unique index, which the
  # rescue folds into the same false.
  def like!(user)
    return false if likes.exists?(user:)

    Reaction.create!(user:, reactable: self, kind: "like")
    increment!(:likes_count, touch: true)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # The like buttons say whether this viewer already liked, as aria-pressed.
  def liked_by?(user)
    user.present? && likes.exists?(user:)
  end
end
