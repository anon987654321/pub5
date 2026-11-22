# frozen_string_literal: true

# Places already have a nullable slug column and a non-unique city/slug index.
# Promote that existing identity to the same city-scoped contract as Events,
# Posts and Marketplace listings. Keep existing unique slugs; fill missing ones;
# make legacy collisions deterministic before enforcing the unique index.
class EnforcePlaceSlugs < ActiveRecord::Migration[8.2]
  INDEX_NAME = "index_places_on_city_id_and_slug"

  def up
    place_rows = Class.new(ActiveRecord::Base) { self.table_name = "places" }
    place_rows.reset_column_information

    used = Hash.new { |cities, city_id| cities[city_id] = {} }
    place_rows.unscoped.order(:city_id, :id).each do |place|
      base = place.slug.to_s.strip.presence || place.name.to_s.parameterize.tr("_", "-")
      base = "place" if base.blank?

      candidate = base
      suffix = 2
      while used[place.city_id].key?(candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end

      used[place.city_id][candidate] = true
      place.update_column(:slug, candidate) unless place.slug == candidate
    end

    remove_index :places, name: INDEX_NAME
    add_index :places, [ :city_id, :slug ], unique: true, name: INDEX_NAME
  end

  def down
    remove_index :places, name: INDEX_NAME
    add_index :places, [ :city_id, :slug ], name: INDEX_NAME
  end
end
