# frozen_string_literal: true

require "test_helper"

class LikeCountStreamTest < ActionDispatch::IntegrationTest
  TURBO = { "Accept" => "text/vnd.turbo-stream.html, text/html" }.freeze

  setup do
    @user = User.strict_loading(false).create!(
      email_address: "liker-#{SecureRandom.hex(4)}@amber.test", password: "password123"
    )
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  test "liking an outfit replaces its button and count in place" do
    outfit = Outfit.create!(user: @user, name: "Høst")

    post like_outfit_path(outfit), headers: TURBO

    assert_response :success
    assert_equal 1, outfit.reload.likes_count
    assert_select "turbo-stream[action=replace][target=?]", "like_outfit_#{outfit.id}" do
      assert_select "template form#like_outfit_#{outfit.id} button", I18n.t("actions.like_count", count: 1)
    end
    assert_select "turbo-stream[action=replace][target=?]", "likes_outfit_#{outfit.id}"
  end

  test "liking an outfit without Turbo still redirects" do
    outfit = Outfit.create!(user: @user, name: "Høst")

    post like_outfit_path(outfit)

    assert_redirected_to outfit_path(outfit)
  end

  test "the outfit page carries the ids the stream targets" do
    outfit = Outfit.create!(user: @user, name: "Høst")

    get outfit_path(outfit)

    assert_select "form#like_outfit_#{outfit.id}"
    assert_select "span#likes_outfit_#{outfit.id}"
  end

  test "liking a post replaces its button in place" do
    record = @user.posts.create!(body: "Ny kåpe")

    post like_post_path(record), headers: TURBO

    assert_response :success
    assert_equal 1, record.reload.likes_count
    assert_select "turbo-stream[action=replace][target=?]", "like_post_#{record.id}" do
      # The name stays stable; the described count is an independently replaceable target.
      assert_select "template form#like_post_#{record.id} button[aria-label=?][aria-describedby=?]",
                    I18n.t("post.like"), ActionView::RecordIdentifier.dom_id(record, :like_count)
      assert_select "template ##{ActionView::RecordIdentifier.dom_id(record, :like_count)}[data-post-like-count=?]",
                    ActionView::RecordIdentifier.dom_id(record), "1"
    end
  end

  test "the feed card offers a comment action without a per-card count query" do
    record = @user.posts.create!(body: "Ny kåpe")

    get posts_path

    assert_response :success
    assert_select ".feed-card-actions a[href=?][aria-label=?]",
                  post_path(record, anchor: "comments"), I18n.t("comments.title")
  end

  test "the detail-page comment action describes its live count target" do
    record = @user.posts.create!(body: "Ny kåpe")
    target = ActionView::RecordIdentifier.dom_id(record, :comment_count)

    get post_path(record)

    assert_response :success
    assert_select ".post-show-actions a[aria-label=?][aria-describedby=?]",
                  I18n.t("comments.title"), target
    assert_select ".post-show-actions span##{target}[data-post-comment-count=?]",
                  ActionView::RecordIdentifier.dom_id(record)
  end

  test "voting a post replaces only the reader's vote rail" do
    record = @user.posts.create!(body: "Ny kåpe")
    target = ActionView::RecordIdentifier.dom_id(record, :vote_rail)

    post post_vote_path(record), params: { vote: { value: 1 } }, headers: TURBO

    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", target do
      assert_select "template div##{target}.post-vote-rail"
      assert_select "template .post-vote-score", "1"
    end
    assert_select "turbo-stream[action=replace][target=?]", ActionView::RecordIdentifier.dom_id(record), 0
  end

  test "liking a post without Turbo still redirects and busts the cached card" do
    record = @user.posts.create!(body: "Ny kåpe")
    before = record.updated_at

    travel 1.second do
      post like_post_path(record)
    end

    assert_redirected_to posts_path
    assert_operator record.reload.updated_at, :>, before
  end

  # Like state is reader-specific; the count remains a separate live target.
  test "like buttons say whether the viewer has liked" do
    record = @user.posts.create!(body: "Ny kåpe")
    outfit = Outfit.create!(user: @user, name: "Høst")

    get post_path(record)
    assert_select "form#like_post_#{record.id} button[aria-pressed=false]"
    get outfit_path(outfit)
    assert_select "form#like_outfit_#{outfit.id} button[aria-pressed=false]"

    post like_post_path(record), headers: TURBO
    assert_select "template form#like_post_#{record.id} button[aria-pressed=true]"
    post like_outfit_path(outfit), headers: TURBO
    assert_select "template form#like_outfit_#{outfit.id} button[aria-pressed=true]"
  end
end
