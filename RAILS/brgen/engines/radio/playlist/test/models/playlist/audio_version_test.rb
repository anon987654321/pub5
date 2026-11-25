# frozen_string_literal: true

require "test_helper"

class Playlist::AudioVersionTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(email_address: "audio_version@brgen.no",
                                               password: "password123", city: @city)
    @track = Playlist::Track.create!(title: "Demo", user: @user)
  end

  test "a byte size cannot be negative and a filename is bounded" do
    version = Playlist::AudioVersion.new(track: @track, byte_size: -1, original_filename: "x" * 256)

    assert_not version.valid?
    assert version.errors.added?(:byte_size, :greater_than_or_equal_to, value: -1, count: 0)
    assert version.errors.added?(:original_filename, :too_long, count: 255)
  end

  test "a version needs only its track; the uploader may be gone" do
    assert Playlist::AudioVersion.new(track: @track).valid?
  end

  test "replacing audio retains the original blob on its version" do
    @track.audio_file.attach(io: StringIO.new("old mix"), filename: "old.mp3", content_type: "audio/mpeg")
    original = @track.audio_file.blob.id

    @track.replace_audio!({ io: StringIO.new("new mix"), filename: "new.mp3", content_type: "audio/mpeg" }, actor: @user)

    version = Playlist::AudioVersion.where(track_id: @track.id).with_attached_audio_file.sole
    assert_equal original, version.audio_file.blob.id
    assert_equal "old mix", version.audio_file.download
    assert_equal "new mix", Playlist::Track.with_attached_audio_file.find(@track.id).audio_file.download
  end

  test "recent lists the newest upload first" do
    older = Playlist::AudioVersion.create!(track: @track, created_at: 2.days.ago)
    newer = Playlist::AudioVersion.create!(track: @track, created_at: 1.hour.ago)

    assert_equal [ newer.id, older.id ], Playlist::AudioVersion.where(track_id: @track.id).recent.ids
  end
end
