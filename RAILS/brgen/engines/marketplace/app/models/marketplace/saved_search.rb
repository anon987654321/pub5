# frozen_string_literal: true

class Marketplace::SavedSearch < ApplicationRecord
  include Shared::Notifiable

  belongs_to :user
  belongs_to :city, optional: true
  before_validation(on: :create) { self.city ||= ActsAsTenant.current_tenant }
  belongs_to :category, class_name: "Marketplace::Category", optional: true

  validates :name, length: { maximum: 120 }, allow_blank: true
  validates :query, length: { maximum: 200 }, allow_blank: true

  # Rows with alerts switched on that the job has not looked at recently. The
  # `notify` column and its "alerts on" chip predate anything that could act on
  # them: saving a search was a bookmark, and ticking the box changed a label.
  scope :alerting, -> { where(notify: true).where.not(city_id: nil).joins(:user).where(users: { deleted_at: nil, deletion_scheduled_at: nil }) }
  scope :for_listing, ->(listing) { listing.city_id ? where(city_id: listing.city_id) : all }
  scope :for_city, ->(city) { where(city_id: [ city&.id, nil ]) }

  # At most one alert per search per this window, however often the job runs.
  # A quarter-hourly job with a chatty seller would otherwise be a notification
  # every fifteen minutes.
  ALERT_INTERVAL = 6.hours

  # Cap per notification. A search for "sykkel" with no category matches half
  # the marketplace on a busy day, and "347 new listings" is not an alert, it is
  # a reason to turn alerts off.
  MAX_LISTINGS_PER_ALERT = 20

  def title
    name.presence || query.presence || strict_safe(:category)&.name || "Saved search"
  end

  def alerts_enabled? = notify? && city_id.present?

  def due_for_alert?(now: Time.current)
    alerts_enabled? && (last_notified_at.nil? || last_notified_at <= now - ALERT_INTERVAL)
  end

  # One listing, on create: the queue never runs, so this is how "alerts on"
  # actually fires. Same predicates as new_matches so a create-time alert and
  # the periodic job cannot disagree.
  def matches_listing?(listing)
    return false if listing.blank? || listing.user_id == user_id
    return false unless city_id && (listing.city_id.nil? || listing.city_id == city_id)
    return false unless Marketplace::Listing.publicly_visible.exists?(id: listing.id)
    return false if category_id.present? && listing.category_id != category_id
    return false if location.present? && listing.location != location
    return true if query.blank?

    Shared::LiveSearch.call(
      Marketplace::Listing.where(id: listing.id),
      query: query,
      columns: %w[title description location]
    ).exists?
  end

  # Listings that appeared since this search last reported. Anchored to
  # created_at on a search that has never alerted, not to the beginning of time
  # — otherwise switching alerts on mails you the entire back catalogue.
  def new_matches(since: nil)
    cutoff = since || last_notified_at || created_at
    return Marketplace::Listing.none unless city_id

    scope = Marketplace::Listing.publicly_visible.where(city_id: [ city_id, nil ]).where.not(user_id: user_id)
                       .where("marketplace_listings.created_at > ?", cutoff)
    scope = scope.where(category_id: category_id) if category_id.present?
    scope = scope.where(location: location) if location.present?
    # Same columns the listings page searches, so an alert cannot disagree with
    # what the "run search" link on this row would show.
    scope = Shared::LiveSearch.call(scope, query: query, columns: %w[title description location]) if query.present?
    scope.order(created_at: :desc)
  end

  # Listings that gained a live Deal (price reduction) matching this search
  # since the last alert. This is the missing half of the original "price-drop
  # alerts" opportunity — new_matches only saw brand-new rows.
  #
  # LiveSearch prefixes columns with the relation's table, so a Deal scope
  # cannot be asked for marketplace_listings.title. Search each table on its
  # own columns and union the ids.
  def price_drop_matches(since: nil)
    cutoff = since || last_notified_at || created_at
    return Marketplace::Deal.none unless city_id

    scope = Marketplace::Deal.live
              .joins(:listing)
              .merge(Marketplace::Listing.publicly_visible.where(city_id: [ city_id, nil ]).where.not(user_id: user_id))
              .where("marketplace_deals.created_at > :cutoff OR marketplace_deals.starts_at > :cutoff", cutoff: cutoff)

    scope = scope.where(marketplace_listings: { category_id: category_id }) if category_id.present?
    scope = scope.where(marketplace_listings: { location: location }) if location.present?

    if query.present?
      listing_hits = Shared::LiveSearch.call(
        Marketplace::Listing.publicly_visible, query: query, columns: %w[title description location]
      )
      headline_hits = Shared::LiveSearch.call(
        Marketplace::Deal.live, query: query, columns: %w[headline]
      )
      scope = scope.where(listing_id: listing_hits.select(:id))
                   .or(scope.where(id: headline_hits.select(:id)))
    end

    scope.includes(:listing).order("marketplace_deals.created_at DESC")
  end

  # Unified entry used by the job. Prefers price drops over plain new listings
  # so a deal on an existing match is not hidden behind "N new listings".
  # Returns [kind, listings] where kind is :price_drop, :new, or nil.
  def matches_for_alert(since: nil)
    drops = price_drop_matches(since: since).limit(MAX_LISTINGS_PER_ALERT).to_a
    return [ :price_drop, drops.map(&:listing) ] if drops.any?

    news = new_matches(since: since).limit(MAX_LISTINGS_PER_ALERT).to_a
    return [ :new, news ] if news.any?

    [ nil, [] ]
  end

  def deliver_alert!(listings, now: Time.current, kind: :new)
    return false if listings.empty?

    with_lock do
      next false unless due_for_alert?(now: now) && self.class.alerting.exists?(id: id)
      next false unless listings.all? { |listing| listing.city_id.nil? || listing.city_id == city_id }

      title_key = kind == :price_drop ? "marketplace.saved_search_alert.price_drop_title" : "marketplace.saved_search_alert.title"
      notification = deliver_notification(
        strict_safe(:user),
        title: I18n.t(title_key, search: title, count: listings.size),
        body: listings.first(3).map(&:title).join(" · "),
        source: self,
        kind: "alert"
      )
      next false unless notification&.persisted?

      update!(last_notified_at: now)
      true
    end
  end
end
