# frozen_string_literal: true

# Shared::Billable declares has_many :referral_credits, and amber's User includes
# Billable, so entitled? reads that table on every entitlement question. brgen got
# it in 20261107100000_create_growth_and_s2s_attribution; amber did not, so the
# first entitlement read raised "Could not find table 'referral_credits'" and the
# account round-trip test errored before it could assert anything.
#
# referral_splinters comes along because it is not optional: Shared::ReferralCredit
# belongs_to :referral_splinter, a required association, and referral_splinter_id
# carries a foreign key. Creating referral_credits alone left that key pointing at
# a table that does not exist -- harmless on SQLite, which does not enforce it, and
# a failing migration on any adapter that does.
#
# s2s_attributions and s2s_conversions are deliberately absent. They share brgen's
# migration, but nothing in this app reads them: no concern includes them and
# amber's User does not. A migration already applied in one app is not the place to
# decide what a different app needs.
#
# Columns and indexes mirror brgen's exactly, so the shared model sees one schema.
class AddReferralCreditsToAmber < ActiveRecord::Migration[8.2]
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
    # brgen's comment applies here too: foreign_key: true already creates the
    # plain FK index, so the unique guard carries its own name.
    add_index :referral_credits, :referral_splinter_id, unique: true,
              name: "index_referral_credits_one_use_per_splinter"
    add_index :referral_credits, %i[user_id entitlement expires_at], name: "index_referral_credits_entitlement"
  end
end
