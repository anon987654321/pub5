# frozen_string_literal: true

# The link-in-bio surface: a creator's public page, the links on it and the
# two events worth counting. Internal links route into gated content through
# the normal access checks; external links are plain redirects. The page is
# the top of the funnel, never a way around the paywall.
class CreateLinktree < ActiveRecord::Migration[8.2]
  def change
    create_table :linktree_pages do |t|
      t.references :creator_profile, null: false, foreign_key: true
      t.string :slug, null: false
      t.json :theme_config, default: {}
      t.timestamps
    end
    add_index :linktree_pages, :slug, unique: true

    create_table :linktree_links do |t|
      t.references :linktree_page, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url
      t.string :icon
      t.integer :position, null: false, default: 0
      t.boolean :visible, default: true, null: false
      t.string :linkable_type
      t.integer :linkable_id
      t.timestamps
    end
    add_index :linktree_links, [ :linktree_page_id, :position ]
    add_index :linktree_links, [ :linkable_type, :linkable_id ]

    create_table :linktree_events do |t|
      t.references :linktree_page, null: false, foreign_key: true
      t.references :linktree_link, foreign_key: true
      t.string :event_type, null: false
      t.string :visitor_hash
      t.string :referrer
      t.timestamps
    end
    add_index :linktree_events, [ :linktree_page_id, :event_type, :created_at ]
  end
end
