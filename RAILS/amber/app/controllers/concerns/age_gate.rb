# frozen_string_literal: true

# The compliance gate for surfaces where a stranger appears on camera. It is
# a before_action on the controller, not a view-level modal, and it reads the
# stored answer (users.age_verified_at) or an approved human identity
# verification - a session flag is not an age check. Guest accounts have
# neither, so stranger video needs a real account.
module AgeGate
  extend ActiveSupport::Concern

  class_methods do
    def age_gate_only(*actions) = before_action(:require_age_verification, only: actions)
  end

  private

  def require_age_verification
    user = Current.user
    return if user.present? && !user.guest? && (user.age_verified? || approved_human_verification?(user))

    redirect_to root_path, alert: t("flash.age_verification_required")
  end

  def approved_human_verification?(user)
    user.identity_verifications.human.approved.exists?
  end
end
