# frozen_string_literal: true

class CreateMarketplaceWholesaleEnquiries < ActiveRecord::Migration[8.2]
  def change
    create_table :marketplace_wholesale_enquiries do |t|
      t.references :store, null: false, foreign_key: { to_table: :marketplace_stores }
      t.references :buyer, null: false, foreign_key: { to_table: :users }
      t.string :buyer_company_name, null: false
      t.string :organisation_number, limit: 9, null: false
      t.string :contact_name, null: false
      t.string :contact_email, null: false
      t.string :contact_phone
      t.text :requested_items, null: false
      t.string :delivery_location, null: false
      t.date :wanted_at
      t.text :seller_response
      t.string :status, default: "submitted", null: false
      t.datetime :responded_at
      t.timestamps

      t.index %i[store_id status created_at],
              name: "idx_marketplace_wholesale_enquiries_store_status_created"
      t.index %i[buyer_id created_at],
              name: "idx_marketplace_wholesale_enquiries_buyer_created"
    end
  end
end
