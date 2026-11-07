# frozen_string_literal: true

class CreateGrowthAndS2sAttribution < ActiveRecord::Migration[8.2]
  def change
    create_table :referral_splinters do |t|
      t.references :referrer, null: false, foreign_key: { to_table: :users }
      t.references :redeemed_by, foreign_key: { to_table: :users }
      t.string :vertical, null: false
      t.string :reward_tier, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :redeemed_at
      t.timestamps
    end
    add_index :referral_splinters, :token_digest, unique: true
    add_index :referral_splinters, :redeemed_by_id, unique: true,
              where: "redeemed_by_id IS NOT NULL", name: "index_referral_splinters_one_claim_per_user"

    create_table :referral_credits do |t|
      t.references :user, null: false, foreign_key: true
      t.references :referral_splinter, null: false, foreign_key: true
      t.string :vertical, null: false
      t.string :entitlement, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :referral_credits, :referral_splinter_id, unique: true
    add_index :referral_credits, %i[user_id entitlement expires_at], name: "index_referral_credits_entitlement"

    create_table :s2s_attributions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :mediago_tracking_id, limit: 500
      t.string :revcontent_rc_uuid, limit: 500
      t.datetime :captured_at, null: false
      t.timestamps
    end
    add_index :s2s_attributions, :user_id, unique: true

    create_table :s2s_conversions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :reference, null: false, limit: 200
      t.integer :amount_cents, null: false
      t.string :currency, null: false, limit: 8, default: "NOK"
      t.string :status, null: false, default: "queued"
      t.json :postback_results, null: false, default: {}
      t.datetime :converted_at, null: false
      t.timestamps
    end
    add_index :s2s_conversions, %i[user_id reference], unique: true,
              name: "index_s2s_conversions_on_user_and_reference"
  end
end
