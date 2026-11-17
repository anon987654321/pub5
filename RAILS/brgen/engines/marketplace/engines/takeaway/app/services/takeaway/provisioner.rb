# frozen_string_literal: true

module Takeaway
  # Creates the Marketplace storefront and the Takeaway kitchen as one tenant
  # operation. A restaurant is not a loose demo record: it has a shop identity,
  # an owner, a city scope and a private draft until the owner publishes it.
  class Provisioner
    DEFAULT_MENU_CATEGORIES = %w[Hovedretter Tilbehør Drikke Desserter].freeze

    Result = Data.define(:restaurant, :store)

    def self.create_restaurant!(owner:, attributes:, marketplace_store: nil, city: nil)
      new(owner:, attributes:, marketplace_store:, city:).create_restaurant!
    end

    def initialize(owner:, attributes:, marketplace_store: nil, city: nil)
      @owner = owner
      @attributes = attributes.to_h.symbolize_keys
      @marketplace_store = marketplace_store
      @city = city
    end

    def create_restaurant!
      raise ArgumentError, "restaurant owner is required" unless @owner&.persisted?
      raise ArgumentError, "restaurant name is required" if @attributes[:name].to_s.strip.empty?

      ActiveRecord::Base.transaction do
        store = find_or_create_store!
        verify_store_owner!(store)
        restaurant = Takeaway::Restaurant.find_by(marketplace_store_id: store.id)

        unless restaurant
          restaurant = @owner.takeaway_restaurants.build(restaurant_attributes)
          restaurant.marketplace_store = store
          restaurant.active = false
          restaurant.demo = false
          restaurant.city = @city || Current.city_record if @city || (Current.respond_to?(:city_record) && Current.city_record)
          restaurant.save!

          DEFAULT_MENU_CATEGORIES.each do |name|
            restaurant.menu_categories.find_or_create_by!(name:)
          end
        end

        Result.new(restaurant:, store:)
      end
    end

    private

    def find_or_create_store!
      return @marketplace_store if @marketplace_store

      slug = @attributes[:store_slug].presence ||
             [@attributes[:name].to_s.parameterize, "restaurant", @owner.id].join("-")
      store = Marketplace::Store.find_or_initialize_by(slug:)
      return store if store.persisted?

      store.assign_attributes(
        owner: @owner,
        name: @attributes[:name].to_s.strip,
        description: @attributes[:description].to_s,
        vertical: "restaurants",
        active: false,
      )
      store.save!
      store
    end

    def verify_store_owner!(store)
      unless store.owner_id == @owner.id && store.vertical == "restaurants"
        raise ActiveRecord::RecordNotFound, "restaurant storefront is not owned by this account"
      end

    end

    def restaurant_attributes
      # :store_slug names the storefront (find_or_create_store! reads it) and
      # is a store attribute like :store_id and :slug — it must not reach the
      # restaurant build, which has no such column. First caller to pass it
      # was seed_mandarinen! (2026-11-17); the UnknownAttributeError it raised
      # took the whole dev seed down, which is how the missing key in this
      # except-list announced itself.
      @attributes.except(:active, :demo, :marketplace_store_id, :store_id, :slug, :store_slug)
                 .except(:city)
                 .merge(active: false, demo: false)
    end
  end
end
