# frozen_string_literal: true

class AddCityToMarketplaceSavedSearches < ActiveRecord::Migration[8.2]
  def change
    # Existing bookmarks have no reliable city provenance. Keep them visible
    # and let their owners resume alerts from the intended city's marketplace.
    add_reference :marketplace_saved_searches, :city, null: true, foreign_key: true
  end
end
