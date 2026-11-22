# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# A reader's post stays in place while its counters move. Content edits still
# refresh the card; votes and comments must not replace somebody else's controls.
class PostLiveCardBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @author = User.strict_loading(false).create!(
      email_address: "live-author-#{SecureRandom.hex(4)}@amber.test", password: "password123"
    )
    @reader = User.strict_loading(false).create!(
      email_address: "live-reader-#{SecureRandom.hex(4)}@amber.test", password: "password123"
    )
    @post = Post.create!(user: @author, body: "Et levende innlegg")
    @post = Post.find(@post.id)
  end

  test "public feed projects comment counts without loading comments per post" do
    Comment.create!(user: @reader, commentable: @post, content: "Godt poeng")

    feed_post = Post.public_feed.find(@post.id)

    assert feed_post.has_attribute?(:feed_comment_count)
    assert_equal 1, feed_post.comment_count
  end

  test "a vote updates the score without refreshing the feed" do
    streams = capture_turbo_stream_broadcasts("posts") do
      Vote.create!(user: @reader, votable: @post, value: 1)
    end

    score = streams.find do |stream|
      stream["targets"] == %([data-post-score="post_#{@post.id}"])
    end
    assert score, "the feed received no score update"
    assert_equal "update", score["action"]
    assert_equal "1", score.at_css("template").inner_html.strip
    assert streams.none? { |stream| stream["action"] == "refresh" || stream["action"] == "replace" },
           "a vote must not redraw the feed or its reader-specific controls"
  end

  test "a comment and its deletion update the shared feed count" do
    comment = nil
    added = capture_turbo_stream_broadcasts("posts") do
      comment = Comment.create!(user: @reader, commentable: @post, content: "Godt poeng")
    end
    assert_count_update(added, "1")
    assert added.none? { |stream| stream["action"] == "refresh" || stream["action"] == "replace" },
           "a comment must not redraw every open feed"

    removed = capture_turbo_stream_broadcasts("posts") { comment.destroy! }
    assert_count_update(removed, "")
    assert removed.none? { |stream| stream["action"] == "refresh" || stream["action"] == "replace" },
           "deleting a comment must not redraw every open feed"
  end

  test "comment changes refresh only subscribers to that post's detail stream" do
    streams = capture_turbo_stream_broadcasts(@post) do
      Comment.create!(user: @reader, commentable: @post, content: "Godt poeng")
    end

    assert streams.any? { |stream| stream["action"] == "refresh" },
           "the open detail thread did not receive a viewer-safe refresh"
  end

  test "a like count has its own targeted update" do
    assert @post.like!(@reader)

    streams = capture_turbo_stream_broadcasts("posts") { @post.broadcast_live_counts }
    update = streams.find do |stream|
      stream["targets"] == %([data-post-like-count="post_#{@post.id}"])
    end

    assert update, "the feed received no like-count update"
    assert_equal "1", update.at_css("template").inner_html.strip
    assert streams.none? { |stream| stream["action"] == "replace" }
  end

  test "a content edit retains the full post-stream refresh" do
    assert_turbo_stream_broadcasts("posts") do
      @post.update!(body: "Et redigert innlegg")
    end
  end

  private

  def assert_count_update(streams, expected)
    update = streams.find do |stream|
      stream["targets"] == %([data-post-comment-count="post_#{@post.id}"])
    end
    assert update, "the detail page received no comment-count update"
    assert_equal "update", update["action"]
    assert_equal expected, update.at_css("template").inner_html.strip
  end
end
