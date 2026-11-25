# frozen_string_literal: true

class AddDatingDiscoveryPreferences < ActiveRecord::Migration[8.2]
  def change
    add_column :dating_profiles, :minimum_partner_age, :integer, default: 18, null: false
    add_column :dating_profiles, :maximum_partner_age, :integer, default: 99, null: false
    add_column :dating_profiles, :relationship_goal, :string
  end
end
