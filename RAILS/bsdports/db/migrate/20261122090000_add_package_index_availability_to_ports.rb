# frozen_string_literal: true

class AddPackageIndexAvailabilityToPorts < ActiveRecord::Migration[8.1]
  def change
    add_column :ports, :available, :boolean, null: false, default: true
    add_column :ports, :package_index_seen_at, :datetime
    add_index :ports, [ :platform_id, :available ]
  end
end
