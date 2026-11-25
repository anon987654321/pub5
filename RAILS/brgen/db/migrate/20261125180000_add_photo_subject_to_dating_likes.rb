# frozen_string_literal: true

class AddPhotoSubjectToDatingLikes < ActiveRecord::Migration[8.2]
  def change
    add_reference :dating_likes, :photo_attachment, foreign_key: { to_table: :active_storage_attachments, on_delete: :nullify }
  end
end
