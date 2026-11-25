# frozen_string_literal: true

class Dating::DislikesController < Dating::BaseController
  before_action :require_user_session
  # A swipe takes any visible user_id; nothing bounded how fast a script could pass.
  rate_limit to: 240, within: 1.hour, only: :create, name: "dislikes",
    with: -> { request.format.json? ? head(:too_many_requests) : redirect_back(fallback_location: root_path, alert: t("shared.flash.rate_limited")) }

  def create
    user = swipe_subjects.includes(:user).find_by!(user_id: params[:user_id]).user
    Dating::Dislike.find_or_create_by!(disliker: Current.user, dislikee: user)
    request.format.json? ? head(:no_content) : redirect_to(root_path)
  end
end
