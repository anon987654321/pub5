# frozen_string_literal: true

class ComicStripsController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]
  before_action :set_comic_strip, only: %i[show]

  def index
    scope = ComicStrip.includes(:user).newest_first
    scope = apply_live_search(scope, columns: %w[prompt style status], vertical: "comic_strips") if live_search_query.present?
    @pagy, @comic_strips = pagy(scope)
    finish_live_search(partial: "comic_strips/live_search_results")
  end

  def show
  end

  def create
    unless ActiveModel::Type::Boolean.new.cast(params[:provider_consent])
      redirect_to root_path, alert: t("comic_strips.create.provider_consent_required"), status: :see_other
      return
    end

    @comic_strip = Current.user.comic_strips.build(comic_strip_params)
    @comic_strip.provider_consent_at = Time.current

    if @comic_strip.save
      GenerateComicStripJob.perform_later(@comic_strip.id)
      redirect_to @comic_strip, notice: t("comic_strips.create.started"), status: :see_other
    else
      redirect_to root_path, alert: @comic_strip.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def set_comic_strip
    @comic_strip = ComicStrip.find(params[:id])
  end

  def comic_strip_params
    params.require(:comic_strip).permit(:prompt, :style)
  end
end
