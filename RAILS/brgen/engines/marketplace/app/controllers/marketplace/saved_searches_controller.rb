# frozen_string_literal: true

class Marketplace::SavedSearchesController < Marketplace::BaseController
  # Every action reads Current.user's searches; without a reader the index
  # raised on nil and answered 500.
  before_action :require_user_session

  def index
    @pagy, @saved_searches = pagy(saved_searches.includes(:category).order(created_at: :desc))
  end

  # An invalid name is a message, not a 500 from create!.
  def create
    saved_search = Current.user.marketplace_saved_searches.new(saved_search_params.merge(city: ActsAsTenant.current_tenant))
    unless saved_search.save
      return redirect_back(fallback_location: listings_path, alert: saved_search.errors.full_messages.to_sentence)
    end

    saved_search.record_activity!("MarketplaceSearchSaved", actor: Current.user, source_vertical: "marketplace",
                                                            locality: saved_search.location, visibility: "private")
    redirect_back fallback_location: listings_path, notice: t("flash.marketplace.search_saved")
  end

  # Alerts on or off from the saved list, without saving the search again.
  def update
    saved_search = saved_searches.find(params[:id])
    notify = ActiveModel::Type::Boolean.new.cast(params[:notify])
    saved_search.city ||= ActsAsTenant.current_tenant if notify
    saved_search.update!(notify: notify)
    redirect_to saved_searches_path,
                notice: t(saved_search.notify? ? "flash.marketplace.alerts_on" : "flash.marketplace.alerts_off")
  end

  def destroy
    saved_searches.find(params[:id]).destroy
    redirect_to saved_searches_path, notice: t("flash.marketplace.search_deleted")
  end

  private

  def saved_searches
    Current.user.marketplace_saved_searches.for_city(ActsAsTenant.current_tenant)
  end

  def saved_search_params
    params.require(:saved_search).permit(:name, :query, :category_id, :location, :notify)
  end
end
