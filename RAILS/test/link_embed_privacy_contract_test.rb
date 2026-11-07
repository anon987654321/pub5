# frozen_string_literal: true

require "minitest/autorun"
require "digest"

# The link-embed facade promises that a page view contacts no provider: the
# player mounts only when the reader presses play, and since shared-029 the
# thumbnail is the app's own cached copy, served from a digest-named endpoint.
#
# The privacy half of that promise is a source contract, because a behavioural
# test needs the network to betray it: any place that renders the provider's
# thumbnail URL into an img src, or a controller that proxies to the provider on
# GET, reintroduces the contact without any test that seeds a provider failing
# to notice. This file reads the owners as text and pins the shape.
class LinkEmbedPrivacyContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SERVICE = File.join(ROOT, "__shared", "app", "services", "shared", "link_embed.rb")
  PARTIAL = File.join(ROOT, "__shared", "app", "views", "shared", "_link_embed.html.erb")
  ROUTES = File.join(ROOT, "__shared", "config", "routes", "social.rb")
  CONTROLLER = File.join(ROOT, "__shared", "app", "controllers", "link_previews_controller.rb")
  JOB = File.join(ROOT, "__shared", "app", "jobs", "shared", "link_embed_job.rb")

  def test_the_facade_serves_the_cached_copy_not_the_provider
    partial = File.read(PARTIAL)
    assert_includes partial, "Shared::LinkEmbed.thumbnail_cached?(embed.thumbnail_url)"
    assert_includes partial, "link_embed_thumbnail_path(Shared::LinkEmbed.thumbnail_digest(embed.thumbnail_url))"
    # The provider's URL never reaches an img src.
    refute_match(/img\s+src="<%=\s*embed\.thumbnail_url/, partial)
  end

  def test_the_route_names_a_digest_and_nothing_else
    routes = File.read(ROUTES)
    assert_match(/get "link_embeds\/thumbnails\/:digest".*link_previews#thumbnail/, routes)
    assert_match(/constraints:\s*\{\s*digest:\s*\/\\A\[0-9a-f\]\{32\}\\z\/\s*\}/, routes)
  end

  def test_the_serving_action_looks_up_the_cache_and_never_proxies
    controller = File.read(CONTROLLER)
    assert_includes controller, "Shared::LinkEmbed.cached_thumbnail(params[:digest].to_s)"
    assert_includes controller, "head :not_found unless found"
    refute_match(/OutboundHttp|Net::HTTP|open_uri|URI\.parse\(params/, controller,
                 "the thumbnail action must serve the cache, not fetch on page view")
    assert_includes controller, "expires_in 1.year, public: true"
  end

  def test_the_cache_is_fetched_where_the_oembed_answer_arrives
    service = File.read(SERVICE)
    # Only known image types enter the cache; the served content type is one of
    # these, never what a provider answered.
    assert_includes service, '"image/jpeg" => ".jpg"'
    assert_includes service, "def fetch_thumbnail(uri)"
    assert_includes service, "Shared::OutboundHttp.request"
    # The digest is content-addressed from the provider URL, hex-only.
    assert_includes service, 'Digest::SHA256.hexdigest(url.to_s)[0, 32]'
    assert_match(/def thumbnail_file\(digest\)\n.*\\A\[0-9a-f\]\{32\}\\z/m, service)

    controller = File.read(CONTROLLER)
    assert_includes controller, "Shared::LinkEmbed.cache_thumbnail!(fresh.thumbnail_url) if fresh.ok?"

    job = File.read(JOB)
    assert_includes job, "Shared::LinkEmbed.cache_thumbnail!(stored.thumbnail_url) if stored.ok?"
  end

  def test_the_digest_endpoint_cannot_traverse
    digest = Digest::SHA256.hexdigest("https://i.ytimg.com/vi/example/hqdefault.jpg")[0, 32]
    assert digest.match?(/\A[0-9a-f]{32}\z/)
    # The route constraint and thumbnail_file both pin 32 lowercase hex chars:
    # dots and slashes never reach a filename.
    ["../etc/passwd", "..%2F..%2Fetc%2Fpasswd", "", "#{digest}/../../x", "#{digest}.jpg"].each do |bad|
      refute bad.match?(/\A[0-9a-f]{32}\z/), "#{bad.inspect} must not pass the digest constraint"
    end
  end
end
