# frozen_string_literal: true

class AddPlaceDirectoryIdentity < ActiveRecord::Migration[8.1]
  def change
    add_column :places, :source, :string, null: false, default: "brgen"
    add_column :places, :external_id, :string
    add_column :places, :verification_state, :string, null: false, default: "unverified"
    add_column :places, :location_precision, :string, null: false, default: "exact"
    add_column :places, :last_observed_at, :datetime

    add_index :places, [ :city_id, :source, :external_id ],
              unique: true, where: "external_id IS NOT NULL",
              name: "index_places_on_city_source_external_id"
    add_index :places, [ :city_id, :verification_state, :kind ],
              name: "index_places_on_city_verification_kind"
  end
end
