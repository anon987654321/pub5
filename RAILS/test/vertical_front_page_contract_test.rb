# frozen_string_literal: true

require "minitest/autorun"

# The front pages share standards, not product identities. This contract guards
# the major interaction each vertical owns and keeps social-post markup scoped
# to the two actual social-post surfaces.
class VerticalFrontPageContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_social_posts_share_one_post_card_and_vote_rail
    brgen = source("brgen/app/views/posts/_post.html.erb")
    amber = source("amber/app/views/posts/_post.html.erb")
    card = source("__shared/app/views/shared/_post_card.html.erb")
    rail = source("__shared/app/views/shared/_post_vote_rail.html.erb")

    assert_includes brgen, 'render "shared/post_card"'
    assert_includes amber, 'render "shared/post_card"'
    assert_includes card, 'class: "feed-card post-reading-card"'
    assert_includes rail, "dom_id(post, :vote_rail)"
  end

  def test_non_post_verticals_keep_their_own_front_page_interactions
    contracts = {
      "marketplace" => [
        "brgen/engines/marketplace/app/views/marketplace/listings/index.html.erb",
        ["bol-market-hero", "listing-kinds"]
      ],
      "dating" => [
        "brgen/engines/dating/app/views/dating/home/index.html.erb",
        ["dating-discover-panel", 'data-controller="swipe"']
      ],
      "tv" => [
        "brgen/engines/radio/tv/app/views/tv/home/index.html.erb",
        ["tv/live_streams_label", "tv/home/trending_videos"]
      ],
      "maps" => [
        "brgen/engines/maps/app/views/maps/home/index.html.erb",
        ["map-morph-guard", "map-point-list"]
      ],
      "takeaway" => [
        "brgen/engines/marketplace/engines/takeaway/app/views/takeaway/restaurants/index.html.erb",
        ["shared/promotional_art", "takeaway-restaurants"]
      ],
      "bsdports" => [
        "bsdports/app/views/ports/index.html.erb",
        ["live_search_index", "auto_discovery_link_tag"]
      ],
      "mrdamascy" => [
        "mrdamascy/app/views/orders/index.html.erb",
        ["order-card", "state_chip(order)"]
      ]
    }

    contracts.each do |vertical, (path, markers)|
      page = source(path)
      markers.each do |marker|
        assert_includes page, marker, "#{vertical} lost its own primary surface marker: #{marker}"
      end
      refute_includes page, "shared/post_card",
                      "#{vertical} is an entity/product surface, not a social-post feed"
    end
  end


  def test_front_pages_keep_distinct_content_postures
    brgen = source("brgen/app/views/home/index.html.erb")
    amber_home = source("amber/app/views/home/index.html.erb")
    amber_posts = source("amber/app/views/home/_frontpage_posts.html.erb")

    assert_includes brgen, "feed-pending"
    assert_includes brgen, "feed-updates"
    assert_includes amber_home, 'render "looks"'
    assert_includes amber_home, 'render "frontpage_posts"'
    assert_includes amber_posts, "amber-home-posts-list"
    refute_includes amber_home, "feed-pending",
                    "Amber's editorial landing page should not inherit Brgen's city-arrival treatment"
  end
end
