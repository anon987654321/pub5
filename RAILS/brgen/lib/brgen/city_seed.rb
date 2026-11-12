# frozen_string_literal: true

require "brgen/domain_registry"

module Brgen
  class CitySeed
    CityRow = Data.define(:domain, :name, :country_code, :locale, :currency, :time_zone, :latitude, :longitude)

    # Seed records derive from the same canonical city catalogue used for host
    # resolution. A missing coordinate or time zone is rejected by DomainRegistry
    # when the catalogue loads; no fallback city list can silently narrow a seed.
    def self.rows_from_registry
      Brgen::DomainRegistry::CITY_RECORDS.map do |record|
        CityRow.new(
          record.fetch("domain"),
          record.fetch("city"),
          record.fetch("country"),
          record.fetch("locale"),
          record.fetch("currency"),
          record.fetch("time_zone"),
          record.fetch("latitude"),
          record.fetch("longitude")
        )
      end
    end

    ROWS = rows_from_registry.freeze

    def self.sync!
      ROWS.each { |row| sync_city(row) }
    end

    def self.sync_city(row)
      City.find_or_initialize_by(domain: row.domain).tap do |city|
        city.country_code = row.country_code
        city.currency = row.currency
        city.latitude = row.latitude
        city.locale = row.locale
        city.longitude = row.longitude
        city.name = row.name
        city.slug = row.domain.parameterize.presence || row.name.parameterize
        city.time_zone = row.time_zone
        city.save!
      end
    end
  end
end
