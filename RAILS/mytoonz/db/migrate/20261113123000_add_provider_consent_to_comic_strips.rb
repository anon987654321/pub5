# frozen_string_literal: true

class AddProviderConsentToComicStrips < ActiveRecord::Migration[8.2]
  def change
    add_column :comic_strips, :provider_consent_at, :datetime
  end
end
