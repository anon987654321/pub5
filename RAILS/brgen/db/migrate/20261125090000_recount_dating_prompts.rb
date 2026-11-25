# frozen_string_literal: true

# Dating::Prompt never maintained Dating::Profile#prompts_count: the
# counter_cache sat on the has_many side, which only reads the column. Every
# profile therefore ranked as having no prompts. The belongs_to now keeps the
# count; this sets existing rows to their true count once.
class RecountDatingPrompts < ActiveRecord::Migration[8.2]
  def up
    execute <<~SQL.squish
      UPDATE dating_profiles
      SET prompts_count = (
        SELECT COUNT(*) FROM dating_prompts WHERE dating_prompts.profile_id = dating_profiles.id
      )
    SQL
  end

  def down
    # Counts are derived data; nothing to restore.
  end
end
