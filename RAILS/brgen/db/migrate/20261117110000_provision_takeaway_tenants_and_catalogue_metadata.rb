# frozen_string_literal: true

class ProvisionTakeawayTenantsAndCatalogueMetadata < ActiveRecord::Migration[8.2]
  def change
    add_reference :takeaway_restaurants, :marketplace_store,
                  index: { unique: true }, foreign_key: { to_table: :marketplace_stores }
    # Retain the richer source menu details that the existing shared Takeaway
    # schema did not have fields for (English name, origin, heat, badges,
    # weights and item-option templates). The operational checkout continues
    # to use its own server-calculated prices and order items.
    add_column :takeaway_menu_items, :metadata, :text
  end
end
