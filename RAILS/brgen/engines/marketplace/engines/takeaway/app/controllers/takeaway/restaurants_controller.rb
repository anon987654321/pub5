# frozen_string_literal: true

class Takeaway::RestaurantsController < Takeaway::BaseController
    include StorefrontSearch

  allow_unauthenticated_access only: %i[index show]
  before_action :require_real_user, except: %i[index show]
  before_action :set_restaurant, only: %i[show edit update destroy]
  before_action :authorize_owner!, only: %i[edit update destroy]
  before_action :load_city_places, only: %i[new create edit update]
  before_action :load_marketplace_store, only: %i[new create]

  def index
    # :city as well as :user — the card renders restaurant.city, which was one
    # query per restaurant (14 on a full page).
    scope = Takeaway::Restaurant.indexable.with_attached_cover.includes(:user, :city)
    @sort = Takeaway::Restaurant::SORTS.include?(params[:sort].to_s) ? params[:sort].to_s : "popular"
    scope = scope.where(cuisine_type: params[:cuisine]) if params[:cuisine].present?
    scope = apply_live_search(scope, columns: %w[name city cuisine_type description], vertical: "takeaway") if live_search_query.present?
    if params[:lat].present? && params[:lng].present?
      scope = scope.near(params[:lat], params[:lng], params[:radius_km] || 5) if scope.respond_to?(:near)
    end
    @pagy, @restaurants = pagy(scope.merge(Takeaway::Restaurant.sorted(@sort)))
    @promo_restaurant, @promo_menu_item = promotional_menu_feature if live_search_query.blank? && params[:cuisine].blank?
    finish_storefront_search(partial: "takeaway/restaurants/live_search_results")
  end

  def show
    return if redirect_id_to_slug(@restaurant)

    @menu_items = @restaurant.menu_items.available.with_attached_photo.includes(:menu_category)
      .order(:menu_category_id, :name).to_a
    @favorited = Current.user.present? && Current.user.takeaway_favorite_restaurants.exists?(restaurant: @restaurant)
    @reviews = load_neighbour_reviews
    @can_review = can_leave_review?
    @nearby_restaurants = nearby_restaurants_for(@restaurant)
  end

  def new
    @restaurant = Takeaway::Restaurant.new
  end

  def create
    result = Takeaway::Provisioner.create_restaurant!(
      owner: Current.user,
      attributes: restaurant_params,
      marketplace_store: @marketplace_store,
    )
    @restaurant = result.restaurant
    redirect_to restaurant_path(@restaurant), notice: t("flash.takeaway.restaurant_created")
  rescue ActiveRecord::RecordInvalid => error
    @restaurant = error.record if error.record.is_a?(Takeaway::Restaurant)
    @restaurant ||= Takeaway::Restaurant.new(restaurant_params)
    render :new, status: :unprocessable_entity
  end

  def edit
    @opening_hours = @restaurant.opening_hours.index_by(&:weekday)
  end

  def update
    was_active = @restaurant.active?
    ActiveRecord::Base.transaction do
      @restaurant.update!(restaurant_params)
      save_opening_hours! if params.key?(:opening_hours)
      if !was_active && @restaurant.active?
        unless @restaurant.menu_items.available.exists? && @restaurant.opening_hours.exists?
          @restaurant.errors.add(:base, t("takeaway.publish_needs_menu_and_hours"))
          raise ActiveRecord::RecordInvalid, @restaurant
        end
      end
      @restaurant.marketplace_store&.update!(active: @restaurant.active?)
    end
    redirect_to restaurant_path(@restaurant)
  rescue ActiveRecord::RecordInvalid => error
    @restaurant = error.record if error.record.is_a?(Takeaway::Restaurant)
    @opening_hours_error = error.message
    @opening_hours = @restaurant.opening_hours.index_by(&:weekday)
    render :edit, status: :unprocessable_entity
  rescue ArgumentError => error
    @opening_hours_error = error.message
    @opening_hours = @restaurant.opening_hours.index_by(&:weekday)
    render :edit, status: :unprocessable_entity
  end

  def destroy
    if @restaurant.orders.exists?
      # A closed kitchen may stop trading, but its orders are the customer's
      # receipt and must outlive the restaurant's public listing.
      @restaurant.update!(active: false)
      @restaurant.marketplace_store&.update!(active: false)
      redirect_to restaurants_path, notice: t("flash.takeaway.restaurant_archived")
    else
      store = @restaurant.marketplace_store
      @restaurant.destroy!
      store&.update!(active: false)
      redirect_to restaurants_path
    end
  end

  private

  # Open or closed for the page's restaurants, read once when the cards ask.
  def open_status = (@open_status ||= Takeaway::OpeningHour.status_for(@restaurants.to_a.map(&:id)))
  helper_method :open_status

  def set_restaurant
    scope = Takeaway::Restaurant.publicly_visible
    scope = scope.or(Takeaway::Restaurant.where(user_id: Current.user.id)) if Current.user
    @restaurant = find_by_slug_or_id(scope, params[:id])
  end

  def load_marketplace_store
    store_id = params[:marketplace_store_id].presence
    @marketplace_store = Current.user.marketplace_stores.find_by!(id: store_id, vertical: "restaurants") if store_id
  end

  def save_opening_hours!
    submitted = params.require(:opening_hours).permit!.to_h
    7.times do |weekday|
      row = submitted.fetch(weekday.to_s, {})
      hour = @restaurant.opening_hours.find_or_initialize_by(weekday:)
      opens_at = row["opens_at"].to_s
      closes_at = row["closes_at"].to_s

      if ActiveModel::Type::Boolean.new.cast(row["closed"]) || (opens_at.blank? && closes_at.blank?)
        hour.destroy! if hour.persisted?
        next
      end

      opens_minute = minute_from_time!(opens_at)
      closes_minute = minute_from_time!(closes_at)
      closes_minute += Takeaway::OpeningHour::DAY_MINUTES if closes_minute <= opens_minute
      hour.assign_attributes(opens_minute:, closes_minute:)
      hour.save!
    end
  end

  def minute_from_time!(value)
    match = value.match(/\\A([01]\\d|2[0-3]):([0-5]\\d)\\z/)
    raise ArgumentError, t("takeaway.opening_hours_invalid_time") unless match

    match[1].to_i * 60 + match[2].to_i
  end

  def authorize_owner!
    redirect_to(restaurants_path, alert: t("flash.takeaway.not_the_owner")) unless @restaurant.owner?(Current.user)
  end

  def restaurant_params = params.require(:restaurant).permit(
    :name,
    :description,
    :address,
    :city,
    :phone,
    :cuisine_type,
    :delivery_fee_cents,
    :min_order_cents,
    :latitude,
    :longitude,
    :active,
    :place_id,
    :cover,
  )

  def load_neighbour_reviews
    base = @restaurant.reviews.includes(:user).order(created_at: :desc).limit(12)
    return base unless authenticated? && Current.user&.latitude

    my_lat = Current.user.latitude.to_f
    my_lng = Current.user.longitude.to_f
    base.select do |r|
      rlat = r.reviewer_lat || r.user&.latitude
      rlng = r.reviewer_lng || r.user&.longitude
      next false unless rlat && rlng
      User.haversine(my_lat, my_lng, rlat.to_f, rlng.to_f) <= 4.0
    end
  end

  def can_leave_review?
    authenticated? && Current.user.takeaway_orders.where(restaurant: @restaurant, status: "delivered").exists?
  end

  def promotional_menu_feature
    restaurant = Takeaway::Restaurant.publicly_visible
      .joins(menu_items: :photo_attachment)
      .merge(Takeaway::MenuItem.available)
      .includes(menu_items: { photo_attachment: :blob })
      .order(rating: :desc, id: :asc)
      .distinct
      .first
    return [ nil, nil ] unless restaurant

    item = restaurant.menu_items.find { |menu_item| menu_item.available? && menu_item.photo.attached? }
    [ restaurant, item ]
  end

  def load_city_places
    city = Current.city_record
    @places = city ? Place.where(city_id: city.id).order(:name) : Place.none
  end

  def nearby_restaurants_for(restaurant)
    return Takeaway::Restaurant.none unless restaurant.geo?

    Takeaway::Restaurant.publicly_visible
      .where.not(id: restaurant.id)
      .nearby(restaurant.latitude, restaurant.longitude, 5)
      .limit(6)
  end
end
