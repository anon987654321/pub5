# frozen_string_literal: true

require "test_helper"

# The default feed lane was the hot decay alone, with no recency floor: one
# well-voted week-old post sat over every fresh one, and a single author could
# hold the top all week. ranked_for is the Dating deck's shape carried to the
# city feed — recency bands, local engagement within a band, and a
# deterministic per-viewer, per-day shuffle — with no model and no RANDOM().
class FeedRankingTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @viewer = User.strict_loading(false).create!(
      email_address: "fr_viewer@brgen.no", password: "password123", username: "fr_viewer", city: @city
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def post(handle:, created_at: Time.current, score: 0, comments: 0, anonymous: false)
    author = User.strict_loading(false).create!(
      email_address: "fr_#{handle}@brgen.no", password: "password123", username: "fr_#{handle}", city: @city
    )
    Post.create!(
      user: author, city: @city, title: "#{handle} sier noe", content: "innhold",
      anonymous: anonymous, created_at: created_at, score: score, comments_count: comments
    )
  end

  test "this morning's post outranks a heavily voted one from last week" do
    stale = post(handle: "stale", created_at: 10.days.ago, score: 400)
    fresh = post(handle: "fresh", created_at: 1.hour.ago)

    ranked = Post.ranked_for(viewer: @viewer).map(&:id)
    assert_operator ranked.index(fresh.id), :<, ranked.index(stale.id)
  end

  test "within a recency band, the engaged-with post outranks the quiet one" do
    quiet = post(handle: "quiet", created_at: 1.hour.ago)
    discussed = post(handle: "discussed", created_at: 2.hours.ago, score: 3, comments: 2)

    ranked = Post.ranked_for(viewer: @viewer).map(&:id)
    assert_operator ranked.index(discussed.id), :<, ranked.index(quiet.id)
  end

  test "the order is deterministic for a viewer and day, and varies by viewer" do
    first_view = Post.ranked_for(viewer: @viewer).map(&:id)
    assert_equal first_view, Post.ranked_for(viewer: @viewer).map(&:id)

    other = User.strict_loading(false).create!(
      email_address: "fr_other@brgen.no", password: "password123", username: "fr_other", city: @city
    )
    # The shuffle permutes only the tail, so two viewers need not see one order;
    # what they must never see is an order that changes between reloads.
    assert_equal Post.ranked_for(viewer: other).map(&:id), Post.ranked_for(viewer: other).map(&:id)
  end

  test "a removed post never appears in the ranked lane" do
    visible = post(handle: "visible")
    removed = post(handle: "removed")
    removed.update_columns(removed_at: Time.current)

    refute_includes Post.ranked_for(viewer: @viewer).map(&:id), removed.id
    assert_includes Post.ranked_for(viewer: @viewer).map(&:id), visible.id
  end

  test "the default lane is ranked_for and the hot tab keeps its own order" do
    default_ids = Post.sorted_lane(nil, viewer: @viewer).map(&:id)
    assert_equal Post.ranked_for(viewer: @viewer).map(&:id), default_ids

    stale = post(handle: "stale2", created_at: 10.days.ago, score: 400)
    fresh = post(handle: "fresh2", created_at: 1.hour.ago)
    hot_ids = Post.sorted_lane("hot", viewer: @viewer).map(&:id)
    assert_operator hot_ids.index(stale.id), :<, hot_ids.index(fresh.id),
                   "hot is the decay leaderboard: votes can hold the top there"
  end

  test "the following lane stays chronological" do
    author = User.strict_loading(false).create!(
      email_address: "fr_followed@brgen.no", password: "password123", username: "fr_followed", city: @city
    )
    Follow.create!(follower: @viewer, followed: author)
    older = Post.create!(user: author, city: @city, title: "eldre", content: "x", anonymous: false,
                         created_at: 3.hours.ago)
    newer = Post.create!(user: author, city: @city, title: "nyere", content: "x", anonymous: false,
                         created_at: 10.minutes.ago)
    # Give the older post the engagement that must NOT reorder this lane.
    older.update_columns(score: 50)

    followed_ids = Post.sorted_lane("following", viewer: @viewer).map(&:id)
    assert_operator followed_ids.index(newer.id), :<, followed_ids.index(older.id),
                   "the people-I-picked lane is chronological on purpose"
  end
end
