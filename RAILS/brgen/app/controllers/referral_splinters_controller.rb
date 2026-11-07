# frozen_string_literal: true

require "openssl"

class ReferralSplintersController < ApplicationController
  before_action :require_user_session, only: %i[create redeem]
  rate_limit to: 5, within: 1.hour, only: :create, name: "referral_splinter_create",
    with: -> { head :too_many_requests }
  before_action :set_token, only: %i[show redeem]

  def create
    vertical = params.require(:vertical).to_s
    return head :forbidden unless milestone_reached?(vertical)

    @vertical = vertical
    @token = Shared::ReferralSplinter.generate!(referrer: Current.user, vertical:)
    @share_url = referral_splinter_url(@token)
    render :show
  rescue ArgumentError
    head :unprocessable_entity
  end

  def show
    @vertical = @splinter.vertical
    @share_url = referral_splinter_url(params[:token])
  end

  def redeem
    Shared::ReferralSplinter.redeem!(token: params[:token], user: Current.user)
    redirect_to root_path, notice: t("growth.referral_redeemed")
  rescue ArgumentError
    redirect_to referral_splinter_path(params[:token]), alert: t("growth.referral_invalid")
  end

  private

  def set_token
    token = params[:token].to_s
    digest = OpenSSL::Digest::SHA256.hexdigest(token)
    @splinter = Shared::ReferralSplinter.find_by(token_digest: digest)
    head :not_found unless @splinter && @splinter.expires_at.future? && @splinter.redeemed_at.nil?
  end

  def milestone_reached?(vertical)
    return false unless Current.user && !Current.user.guest? && Current.user.deleted_at.nil?

    case vertical
    when "playlist"
      defined?(Playlist::Playlist) &&
        Playlist::Playlist.where(user_id: Current.user.id, public_access: true).where("plays_count >= ?", 100).exists?
    when "dating"
      defined?(Dating::Profile) && Dating::Profile.where(user_id: Current.user.id).where.not(verified_at: nil).exists?
    else
      false
    end
  end
end
