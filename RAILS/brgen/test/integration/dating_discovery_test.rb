# frozen_string_literal: true

require "test_helper"

# Dating::Profile.oriented_for enforces mutual gender preference so discovery is
# a dating deck, not a random-person feed.
class DatingDiscoveryTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
  end
  teardown { ActsAsTenant.current_tenant = nil }

  def profile(gender, looking_for)
    u = User.create!(email_address: "d-#{SecureRandom.hex(4)}@brgen.no",
                     password: "password12345", username: "d_#{SecureRandom.hex(3)}", city: @city)
    profile = Dating::Profile.new(user: u, gender:, looking_for:, visible: true, age: 30)
    attach_pixel!(profile.photos)
    profile.save!
    profile
  end

  test "a man looking for women sees women who want men, not other men" do
    viewer = profile("man", "woman")
    she = profile("woman", "man")      # mutual → shown
    other = profile("man", "woman")      # wrong gender → hidden
    picky = profile("woman", "woman")    # doesn't want men → hidden
    ids = Dating::Profile.oriented_for(viewer).pluck(:id)
    assert_includes ids, she.id
    assert_not_includes ids, other.id
    assert_not_includes ids, picky.id
  end

  test "everyone / unset stays open both ways" do
    viewer = profile("nonbinary", "everyone")
    open = profile("man", "everyone")
    ids = Dating::Profile.oriented_for(viewer).pluck(:id)
    assert_includes ids, open.id
  end

  test "nonbinary and other gender preferences apply mutually" do
    viewer = profile("woman", "nonbinary")
    mutual = profile("nonbinary", "woman")
    wrong_preference = profile("nonbinary", "man")
    wrong_gender = profile("other", "woman")

    ids = Dating::Profile.oriented_for(viewer).ids
    assert_includes ids, mutual.id
    assert_not_includes ids, wrong_preference.id
    assert_not_includes ids, wrong_gender.id
    assert_includes Dating::Profile.oriented_for(profile("woman", "other")).ids, wrong_gender.id
  end

  test "matches hide blocks in either direction" do
    viewer = profile("woman", "everyone")
    first = profile("man", "everyone")
    second = profile("nonbinary", "everyone")
    third = profile("other", "everyone")
    Dating::Match.insert_all!([ first, second, third ].map { |candidate| { initiator_id: viewer.user_id, receiver_id: candidate.user_id, status: "matched" } })
    Block.create!(blocker_id: viewer.user_id, blocked_id: first.user_id)
    Block.create!(blocker_id: second.user_id, blocked_id: viewer.user_id)

    assert_equal [ third.user_id ], Dating::Match.active.visible_to(viewer.user).pluck(:receiver_id)
  end

  test "a dating profile requires an adult age" do
    u = User.create!(email_address: "age-#{SecureRandom.hex(4)}@brgen.no",
                     password: "password12345", username: "a_#{SecureRandom.hex(3)}", city: @city)
    missing = Dating::Profile.new(user: u, visible: true)
    under = Dating::Profile.new(user: u, visible: true, age: 17)

    assert_not missing.valid?
    assert_not under.valid?
  end

  test "visible discovery excludes accounts leaving or already deleted" do
    leaving = profile("woman", "man")
    deleted = profile("woman", "man")
    leaving.user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)
    deleted.user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 1.day.ago)

    ids = Dating::Profile.visible.pluck(:id)

    assert_not_includes ids, leaving.id
    assert_not_includes ids, deleted.id
  end

  test "visible discovery never includes anyone under 18" do
    adult = profile("woman", "man")
    ids = Dating::Profile.visible.pluck(:id)

    assert_includes ids, adult.id
    assert Dating::Profile.visible.where("age < 18").none?
  end
end
