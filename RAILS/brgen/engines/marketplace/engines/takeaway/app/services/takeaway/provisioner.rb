# frozen_string_literal: true

module Takeaway
  # Creates the Marketplace storefront and the Takeaway kitchen as one tenant
  # operation. A restaurant is not a loose demo record: it has a shop identity,
  # an owner, a city scope and a private draft until the owner publishes it.
  class Provisioner
    DEFAULT_MENU_CATEGORIES = %w[Hovedretter Tilbehør Drikke Desserter].freeze

    Result = Data.define(:restaurant, :store)

    def self.create_restaurant!(owner:, attributes:, marketplace_store: nil)
      new(owner:, attributes:, marketplace_store:).create_restaurant!
    end

    def initialize(owner:, attributes:, marketplace_store: nil)
      @owner = owner
      @attributes = attributes.to_h.symbolize_keys
      @marketplace_store = marketplace_store
    end

    def create_restaurant!
      raise ArgumentError, "restaurant owner is required" unless @owner&.persisted?
      raise ArgumentError, "restaurant name is required" if @attributes[:name].to_s.strip.empty?

      ActiveRecord::Base.transaction do
        store = find_or_create_store!
        verify_store_owner!(store)

        restaurant = @owner.takeaway_restaurants.build(restaurant_attributes)
        restaurant.marketplace_store = store
        restaurant.active = false
        restaurant.demo = false
        restaurant.city = Current.city_record if Current.respond_to?(:city_record) && Current.city_record
        restaurant.save!

        DEFAULT_MENU_CATEGORIES.each do |name|
          restaurant.menu_categories.find_or_create_by!(name:)
        end

        Result.new(restaurant:, store:)
      end
    end

    private

    def find_or_create_store!
      return @marketplace_store if @marketplace_store

      slug = [
        @attributes[:name].to_s.parameterize,
        "restaurant",
        @owner.id,
        SecureRandom.hex(3),
      ].join("-")

      Marketplace::Store.create!(
        owner: @owner,
        name: @attributes[:name].to_s.strip,
        slug:,
        description: @attributes[:description].to_s,
        vertical: "restaurants",
        active: false,
      )
    end

    def verify_store_owner!(store)
      unless store.owner_id == @owner.id && store.vertical == "restaurants"
        raise ActiveRecord::RecordNotFound, "restaurant storefront is not owned by this account"
      end
      if Takeaway::Restaurant.where(marketplace_store_id: store.id).exists?
        raise ActiveRecord::RecordInvalid, store
      end
    end

    def restaurant_attributes
      @attributes.except(:active, :demo, :marketplace_store_id, :store_id, :slug)
                 .except(:city)
                 .merge(active: false, demo: false)
    end
  end
end
