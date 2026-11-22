# frozen_string_literal: true

# The ledger is the durable journal for credits and entitlements. This first
# migration deliberately adds no payment route, provider credential or checkout
# table; money movement stays on the existing provider-specific paths.
class CreateCommerceLedgerEntries < ActiveRecord::Migration[8.2]
  def change
    create_table :commerce_ledger_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :entry_type, limit: 32, null: false
      t.string :idempotency_key, limit: 160, null: false
      t.string :entitlement, limit: 64, null: false
      t.datetime :expires_at
      t.bigint :amount_minor
      t.string :currency, limit: 3
      t.string :source_type
      t.integer :source_id
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :commerce_ledger_entries, :idempotency_key, unique: true
    add_index :commerce_ledger_entries, [ :source_type, :source_id ],
              name: "index_commerce_ledger_entries_on_source"
    add_index :commerce_ledger_entries, [ :user_id, :created_at ],
              name: "index_commerce_ledger_entries_on_user_and_time"
  end
end
