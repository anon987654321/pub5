# frozen_string_literal: true

require "test_helper"

class Brgen::HomeFeedTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @reader = make_user("cold_reader")
    @followed = make_user("cold_followed")
    @other = make_user("cold_other")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "following? detects following feed param" do
    assert Brgen::HomeFeed.following?(feed: "following")
    assert_not Brgen::HomeFeed.following?(feed: nil)
    assert_not Brgen::HomeFeed.following?(feed: "for_you")
  end

  test "an empty Following graph gets followed posts plus city popular posts" do
    mine = create_post(@reader, "Own post")
    local = create_post(@other, "Popular city post")
    local.update_column(:score, 20)

    assert Brgen::HomeFeed.following_cold_start?(feed: "following", authenticated: true, user: @reader)
    feed = Brgen::HomeFeed.scope(feed: "following", authenticated: true, user: @reader).to_a

    assert_includes feed.map(&:id), mine.id
    assert_includes feed.map(&:id), local.id
    assert_equal local.id, feed.first.id, "existing decayed-hot ranking puts the more-engaged city post first"
    assert feed.all? { |post| post.city_id == @city.id }
  end

  test "a reader with follows keeps the normal Following-only timeline" do
    followed_post = create_post(@followed, "Followed post")
    other_post = create_post(@other, "Unfollowed post")
    @reader.follow!(@followed)

    refute Brgen::HomeFeed.following_cold_start?(feed: "following", authenticated: true, user: @reader)
    feed = Brgen::HomeFeed.scope(feed: "following", authenticated: true, user: @reader)

    assert_includes feed.map(&:id), followed_post.id
    refute_includes feed.map(&:id), other_post.id
  end

  test "the fallback is restricted to the authenticated Following lane" do
    assert_not Brgen::HomeFeed.following_cold_start?(feed: "following", authenticated: false, user: @reader)
    assert_not Brgen::HomeFeed.following_cold_start?(feed: nil, authenticated: true, user: @reader)
    assert_not Brgen::HomeFeed.following_cold_start?(feed: "communities", authenticated: true, user: @reader)
  end

  private

  def make_user(name)
    User.create!(
      email_address: "#{name}-#{SecureRandom.hex(4)}@brgen.no",
      password: "password12345",
      username: "#{name}_#{SecureRandom.hex(3)}",
      guest: false,
      city: @city
    )
  end

  def create_post(author, title)
    Post.create!(user: author, title:, content: "A local post", city: @city)
  end
end
