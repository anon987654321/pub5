# frozen_string_literal: true

class PairController < ApplicationController
  skip_before_action :verify_authenticity_token, only: %i[create issue destroy]
  before_action :require_same_origin!, only: %i[create issue destroy]
  skip_before_action :require_container!
  before_action :enforce_pair_redeem_rate_limit, only: :create
  before_action :require_authenticated!, only: %i[admin issue_admin destroy_admin issue list destroy]

  def admin
    @pairings = Master::Ground::Pairing.list.sort_by { |row| row[:paired_at].to_i }.reverse
    render layout: false
  end

  # The one-time code is shown only in this redirect's flash. Redeemed tokens
  # are never returned to this page; they are represented only by subject,
  # label and paired time, and remain active until explicitly revoked.
  def issue_admin
    issued = Master::Ground::Pairing.issue(label: params[:label].to_s)
    flash[:pair_code] = issued.fetch(:code)
    flash[:pair_code_expires_in] = issued.fetch(:expires_in)
    redirect_to pair_admin_path, status: :see_other
  end

  def destroy_admin
    ok = Master::Ground::Pairing.revoke(params[:subject].to_s)
    redirect_to pair_admin_path,
                status: :see_other,
                notice: (ok ? "Pairing revoked." : "Pairing not found.")
  end

  def show
    with_master_fiber(unlocked: unlocked?) do
      render json: Master::Ground::Pairing.status(cookies[:master_paired].to_s).merge(
        profile: face_profile,
        notice: face_profile == "public" ? Master::Ground::Pairing::REDEEM_NOTICE : nil,
      )
    end
  end

  def create
    result = Master::Ground::Pairing.redeem(params[:code].to_s)
    unless result
      render json: { ok: false, error: "invalid or expired code" }, status: :unprocessable_entity
      return
    end

    set_pair_cookie(result[:token])
    render json: { ok: true, profile: "messaging", subject: result[:subject], notice: Master::Ground::Pairing.redeem_notice(result) }
  end

  def issue
    issued = Master::Ground::Pairing.issue(label: params[:label].to_s)
    render json: issued.merge(ok: true)
  end

  def list
    render json: { rows: Master::Ground::Pairing.list }
  end

  def destroy
    ok = Master::Ground::Pairing.revoke(params[:subject].to_s)
    render json: { ok: }, status: (ok ? :ok : :not_found)
  end
end
