# frozen_string_literal: true

# A one-way mute-and-hide: blocker no longer sees blocked's content. Silent by
# design — the blocked user is never notified.
class Block < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocker_id, uniqueness: { scope: :blocked_id }
  validate :no_self_block

  def self.counterparts_for(user)
    outgoing = where(blocker_id: user.id).select(:blocked_id)
    incoming = where(blocked_id: user.id).select(:blocker_id)
    User.where(id: outgoing).or(User.where(id: incoming)).select(:id)
  end

  private

  def no_self_block
    errors.add(:base, :self_block) if blocker_id == blocked_id
  end
end
