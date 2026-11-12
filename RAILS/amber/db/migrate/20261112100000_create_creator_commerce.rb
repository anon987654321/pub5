# frozen_string_literal: true

# The entitlement spine and the Vipps payment rail.
#
# An Entitlement answers the one question the gated surfaces ask: does this
# user currently hold access to this specific thing? A subject row (a Post, a
# LiveStream) names the thing; an entitlement_name alone names a plan-style
# grant with no single subject. A PaymentTransaction records the money fact
# that granted it, whichever rail carried the payment.
class CreateCreatorCommerce < ActiveRecord::Migration[8.2]
  def change
    create_table :entitlements do |t|
      t.references :user, null: false, foreign_key: true
      t.string :subject_type
      t.integer :subject_id
      t.string :entitlement_name
      t.string :source, null: false, default: "ppv"
      t.datetime :expires_at
      t.timestamps
    end
    add_index :entitlements, [ :subject_type, :subject_id ]
    add_index :entitlements, [ :user_id, :entitlement_name ]
    add_index :entitlements, [ :user_id, :subject_type, :subject_id, :source ],
              name: "index_entitlements_on_user_and_subject_and_source", unique: true

    create_table :payment_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :rail, null: false, default: "vipps"
      t.string :reference, null: false
      t.integer :amount_minor, null: false
      t.string :currency, null: false, default: "NOK"
      t.string :state, null: false, default: "pending"
      t.string :purchasable_type
      t.integer :purchasable_id
      t.timestamps
    end
    add_index :payment_transactions, [ :rail, :reference ], unique: true
    add_index :payment_transactions, [ :purchasable_type, :purchasable_id ]

    create_table :vipps_payments do |t|
      t.references :user, null: false, foreign_key: true
      t.string :reference, null: false
      t.integer :amount_minor, null: false
      t.string :currency, null: false, default: "NOK"
      t.string :state, null: false, default: "CREATED"
      t.string :idempotency_key, null: false
      t.string :purchasable_type
      t.integer :purchasable_id
      t.timestamps
    end
    add_index :vipps_payments, :reference, unique: true
    add_index :vipps_payments, [ :purchasable_type, :purchasable_id ]

    create_table :vipps_agreements do |t|
      t.references :user, null: false, foreign_key: true
      t.string :agreement_id, null: false
      t.string :entitlement_name, null: false
      t.integer :amount_minor, null: false
      t.string :currency, null: false, default: "NOK"
      t.string :interval, null: false, default: "MONTH"
      t.string :state, null: false, default: "PENDING"
      t.timestamps
    end
    add_index :vipps_agreements, :agreement_id, unique: true

    # Pay-per-view on a Post: a price in minor units makes it gated; nil or
    # zero keeps it free. The buyer's permanent unlock is an Entitlement row.
    add_column :posts, :price_minor, :integer
    add_column :posts, :currency, :string

    # A ticketed live stream: access costs price_minor unless the viewer holds
    # the entitlement, the premium plan, or the host's chair.
    add_column :live_streams, :ticketed, :boolean, default: false, null: false
    add_column :live_streams, :price_minor, :integer

    # The compliance gate's stored answer. The verification vendor writes it;
    # the app only reads it, so no identity data lives here.
    add_column :users, :age_verified_at, :datetime
  end
end
