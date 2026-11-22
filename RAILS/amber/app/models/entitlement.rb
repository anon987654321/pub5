# frozen_string_literal: true

# The one answer every gated surface asks: does this user currently hold
# access to this specific thing? A subject row names the thing (a Post, a
# LiveStream); an entitlement_name alone names a plan-style grant. expires_at
# nil means the grant is permanent - a PPV unlock never silently rots.
class Entitlement < ApplicationRecord
  SOURCES = %w[ppv live_ticket subscription referral].freeze

  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true

  validates :source, inclusion: { in: SOURCES }
  validates :entitlement_name, presence: true, unless: -> { subject.present? }
  validate :subject_or_name, on: :create

  scope :live, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }
  scope :for_subject, ->(subject) { where(subject_type: subject.class.name, subject_id: subject.id) }

  class << self
    # Idempotent on (user, subject, source): a retried webhook grants once.
    def grant!(user, subject: nil, source: "ppv", entitlement_name: nil, expires_at: nil)
      scope = where(user:, source:)
      scope = subject ? scope.for_subject(subject) : scope.where(entitlement_name:)
      scope.where(expires_at: [ nil, expires_at ]).first_or_create!(
        subject:, entitlement_name:, expires_at:
      )
    end
  end

  def live? = expires_at.nil? || expires_at > Time.current

  private

  def subject_or_name
    return if subject.present? || entitlement_name.present?

    errors.add(:entitlement_name, "or a subject must name what the entitlement opens")
  end
end
