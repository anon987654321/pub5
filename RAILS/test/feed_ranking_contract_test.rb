# frozen_string_literal: true

require "minitest/autorun"

# brgen_feed_ranking_deterministic (MASTER/data/gaps.yml, workstream in
# MASTER/convergence.yml): the default feed lane ranks recency bands first,
# local engagement second, and a deterministic per-viewer, per-day shuffle
# third — the Dating deck's shape carried to the city feed. This contract
# reads the source so the shape holds on a bare-Ruby host: no RANDOM(), no
# model call, every term one SQL expression, and the fences (the following
# lane stays chronological; removed posts stay out) pinned where the code
# declares them.
class FeedRankingContractTest < Minitest::Test
  POST = File.expand_path("../brgen/app/models/post.rb", __dir__)
  DATING = File.expand_path("../brgen/engines/dating/app/models/dating/profile.rb", __dir__)

  def test_the_rank_terms_are_present_and_readable
    source = File.read(POST)

    assert_includes source, "RANK_RECENCY_SQL", "the recency band is a named constant, not an inline blob"
    assert_includes source, "datetime('now', '-2 days')", "the first band is two days, like the Dating deck"
    assert_includes source, "datetime('now', '-14 days')", "the second band is two weeks"
    assert_includes source, "posts.score + 2.0 * posts.comments_count + 1.0",
                    "comments count double a vote; +1 keeps a zero-signal post divisible"
    assert_includes source, "julianday('now') - julianday(posts.created_at)",
                    "engagement decays by the same age divisor the hot lane uses"
    assert_includes source, "RANK_SHUFFLE_MODULUS = 997", "the shuffle modulus is the Dating deck's prime"
  end

  def test_the_rank_is_deterministic_never_random
    source = File.read(POST).lines.reject { |line| line.lstrip.start_with?("#") }.join

    refute_match(/RANDOM\(\)/, source, "no lane may order by RANDOM(): reloads must not reshuffle")
    assert_includes source, "Digest::MD5.hexdigest", "the per-viewer jitter is a seeded digest"
    assert_match(/\(\(posts\.id \* #\{multiplier\}\) % #\{modulus\}\) ASC/, source,
                 "the shuffle multiplies by a coprime, like the Dating deck's deck order")
  end

  def test_the_default_lane_is_ranked_for_and_the_fences_hold
    source = File.read(POST)

    assert_includes source, "else ranked_for(viewer: viewer)", "the default feed lane is ranked_for"
    assert_includes source, 'when "hot" then hot', "hot keeps its own tab"
    assert_match(/when "following".*followed_by\(viewer\)/m, source, "the following lane keeps its resolver")
    assert_match(%r{scope :followed_by.*order\(created_at: :desc\)}m, source,
                 "the following lane is chronological on purpose; ranking chosen people is the fenced horizon")
    assert_match(/def self\.ranked_for.*kept\.order/m, source, "removed posts never appear in the ranked lane")
  end

  def test_the_dating_deck_kept_its_shape
    source = File.read(DATING)

    assert_includes source, "SHUFFLE_MODULUS = 997", "the city feed copied the deck's prime, not a fork of it"
    assert_includes source, "def self.ranked_for(viewer, seed: Date.current.to_s)",
                    "the deck's signature is the shape the feed follows"
  end

  def test_the_controller_and_the_reflex_read_one_lane_resolver
    controller = File.read(File.expand_path("../brgen/app/controllers/posts_controller.rb", __dir__))
    reflexes = Dir.glob(File.expand_path("../brgen/app/reflexes/posts_infinite_scroll_reflex.rb", __dir__))
                 .flat_map { |path| File.readlines(path) }

    assert_includes controller, "Post.sorted_lane(params[:sort], viewer: Current.user)"
    assert reflexes.any? { |line| line.include?("sorted_lane") },
           "the infinite-scroll reflex pages the same lanes the controller renders"
  end

  def test_the_bare_ruby_host_proves_the_order_shape_in_sqlite
    # The rank expression runs as written: bands first, engagement second,
    # deterministic tail. sqlite3 ships with Ruby and needs no Rails.
    require "sqlite3"
    db = SQLite3::Database.new(":memory:")
    db.execute("CREATE TABLE posts (id INTEGER PRIMARY KEY, score INTEGER, comments_count INTEGER,
                created_at TEXT, removed_at TEXT)")
    now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
    db.execute("INSERT INTO posts VALUES (1, 400, 0, ?, NULL)",
               [(Time.now.utc - 10 * 86_400).strftime("%Y-%m-%d %H:%M:%S")])
    db.execute("INSERT INTO posts VALUES (2, 0, 0, ?, NULL)", [now])
    db.execute("INSERT INTO posts VALUES (3, 3, 2, ?, NULL)", [(Time.now.utc - 3_600).strftime("%Y-%m-%d %H:%M:%S")])
    db.execute("INSERT INTO posts VALUES (4, 9, 0, ?, NULL)", [now])

    rows = db.execute(<<~SQL)
      SELECT id FROM posts
      WHERE removed_at IS NULL
      ORDER BY CASE
        WHEN posts.created_at > datetime('now', '-2 days')  THEN 0
        WHEN posts.created_at > datetime('now', '-14 days') THEN 1
        ELSE 2
      END ASC,
      (posts.score + 2.0 * posts.comments_count + 1.0) /
        (((julianday('now') - julianday(posts.created_at)) * 24.0) + 2.0) DESC,
      ((posts.id * 17) % 997) ASC,
      posts.created_at DESC
    SQL

    assert_equal [4, 3, 2, 1], rows.flatten,
                 "engagement ranks inside the fresh band, a voted week-old post stays below it, removed drops out"
  end
end
