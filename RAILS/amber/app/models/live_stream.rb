# frozen_string_literal: true

class LiveStream < ApplicationRecord
  STATUSES = %w[scheduled live ended cancelled].freeze

  belongs_to :user

  scope :publicly_visible, -> { joins(:user).where(users: { deleted_at: nil, deletion_scheduled_at: nil }) }

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :upcoming, -> { where(status: "scheduled").order(:scheduled_at, :created_at) }
  scope :live, -> { where(status: "live") }

  def start! = update!(status: "live", started_at: Time.current)
  def end! = update!(status: "ended", ended_at: Time.current)
  def cancel! = update!(status: "cancelled")

  def host?(user) = user.present? && user_id == user.id

  # A ticketed stream answers the same question a PPV post does: the host's
  # chair is open, Amber Premium is open, and a ticket (an Entitlement row)
  # opens one seat. A free stream is open to everyone.
  def accessible_by?(user)
    return true unless ticketed?
    return false if user.nil?

    host?(user) || user.entitled_to?(self)
  end
end
