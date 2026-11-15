# frozen_string_literal: true

class ResourcesController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]
  before_action :require_real_user, except: %i[index show]
  before_action :set_resource, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    scope = Resource.includes(:category).verified.order(:title)
    scope = scope.by_type(params[:type]) if params[:type].present?
    scope = apply_live_search(scope, columns: %w[title description resource_type], vertical: "resources") if live_search_query.present?
    @pagy, @resources = pagy(scope)
    @crisis_lines = Crisis.all
    finish_live_search(partial: "resources/live_search_results")
  end

  def show
    @resource.record_activity!("ResourceViewed", source_vertical: "hjerterom")
  end

  def new
    @resource = Current.user.resources.build
  end

  def create
    @resource = Current.user.resources.build(resource_params)
    if @resource.save
      @resource.record_activity!("ResourceCreated", source_vertical: "hjerterom")
      redirect_to(@resource, notice: t("flash.resource_submitted"))
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def edit; end

  def update
    if @resource.update(resource_params)
      @resource.record_activity!("ResourceUpdated", source_vertical: "hjerterom")
      redirect_to(@resource, notice: t("flash.updated"))
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    @resource.record_activity!("ResourceRemoved", source_vertical: "hjerterom")
    @resource.destroy
    redirect_to resources_path, notice: t("flash.removed")
  end

  private

  def set_resource  = @resource = Resource.find(params[:id])
  def authorize!
    redirect_to(resources_path, alert: t("flash.unauthorized")) unless @resource.user == Current.user
  end

  def resource_params
    params.require(:resource).permit(
      :title, :description, :url, :address, :city, :postal_code,
      :phone, :email, :resource_type, :opening_hours, :category_id
    )
  end
end
