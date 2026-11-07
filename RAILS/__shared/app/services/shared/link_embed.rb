# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"
require "yaml"

module Shared
  # Media players for the links people put in posts, resolved once and rendered
  # from what was stored. brgen's front page and amber's feed share it.
  #
  # A link is only ever parsed for the id it names. The URL a reader pasted is
  # never fetched: the one request goes to the provider's public oEmbed endpoint,
  # a fixed HTTPS address, through Shared::OutboundHttp. The player is rebuilt
  # from the id, so nothing the provider sends back is ever rendered as markup.
  module LinkEmbed
    # One service whose links a post may embed: the exact hosts its links live
    # on, the path shapes that name one piece of media, its oEmbed endpoint, and
    # the player built from the id.
    #
    # Hosts are compared whole, never by suffix or substring, so
    # youtube.com.evil.test and notyoutube.com name nothing.
    Provider = Data.define(:key, :label, :hosts, :media_id, :canonical, :oembed, :player, :thumbnail_hosts, :allow) do
      def match(uri)
        return unless hosts.include?(uri.host.to_s.downcase)

        media_id.call(uri)
      end

      def canonical_url(id) = canonical.call(id)
      def player_url(id) = player.call(id)

      def oembed_uri(id)
        URI("#{oembed}?#{URI.encode_www_form(format: "json", url: canonical_url(id))}")
      end

      # A thumbnail is shown before the reader asks for anything, so it may only
      # come from the provider's own image host.
      def thumbnail?(url)
        uri = URI(url.to_s)
        uri.is_a?(URI::HTTPS) && uri.port == 443 && thumbnail_hosts.any? { |host| host === uri.host.to_s.downcase }
      rescue URI::InvalidURIError
        false
      end
    end

    # A link that one provider recognised, and the id it names.
    Match = Data.define(:provider, :media_id, :source_url) do
      def canonical_url = provider.canonical_url(media_id)
    end

    YOUTUBE_ID = /\A[\w-]{11}\z/
    YOUTUBE_PATH = %r{\A/(?:shorts|embed|live)/([\w-]+)/?\z}
    SOUNDCLOUD_PATH = %r{\A/([a-z0-9][\w-]*)/((?:sets/)?[a-z0-9][\w-]*)/?\z}i
    # First path segments that are SoundCloud's own pages rather than an artist.
    SOUNDCLOUD_PAGES = %w[
      discover search stream upload you charts pages jobs terms-of-use mobile settings messages
    ].freeze
    VIMEO_PATH = %r{\A/(\d+)(?:/([0-9a-f]+))?/?\z}
    # /tracks/<id> with an optional title slug after it.
    WHYP_PATH = %r{\A/tracks/([A-Za-z0-9_-]+)(?:/[A-Za-z0-9_-]+)?/?\z}
    WHYP_TOKEN = /\A[A-Za-z0-9_-]{1,64}\z/
    SPOTIFY_PATH =%r{\A/(?:intl-[a-z]{2}(?:-[a-z]{2})?/)?(track|album|playlist|episode|show)/([A-Za-z0-9]{22})/?\z}

    PROVIDERS = [
      Provider.new(
        key: "youtube", label: "YouTube",
        hosts: %w[youtube.com www.youtube.com m.youtube.com youtu.be],
        media_id: lambda { |uri|
          id = uri.path[YOUTUBE_PATH, 1]
          id = URI.decode_www_form(uri.query.to_s).to_h["v"] if uri.path == "/watch"
          id = uri.path.delete_prefix("/") if uri.host.to_s.downcase == "youtu.be"
          id if id.to_s.match?(YOUTUBE_ID)
        },
        canonical: ->(id) { "https://www.youtube.com/watch?v=#{id}" },
        oembed: "https://www.youtube.com/oembed",
        # youtube-nocookie sets no tracking cookie until the reader presses play.
        player: ->(id) { "https://www.youtube-nocookie.com/embed/#{id}?autoplay=1" },
        thumbnail_hosts: %w[i.ytimg.com],
        allow: "autoplay; encrypted-media; fullscreen; picture-in-picture"
      ),
      Provider.new(
        key: "soundcloud", label: "SoundCloud",
        hosts: %w[soundcloud.com www.soundcloud.com m.soundcloud.com],
        media_id: lambda { |uri|
          user, item = uri.path.match(SOUNDCLOUD_PATH)&.captures
          "#{user}/#{item}".downcase if user && !SOUNDCLOUD_PAGES.include?(user.downcase)
        },
        canonical: ->(id) { "https://soundcloud.com/#{id}" },
        oembed: "https://soundcloud.com/oembed",
        player: lambda { |id|
          track = CGI.escape("https://soundcloud.com/#{id}")
          "https://w.soundcloud.com/player/?url=#{track}&auto_play=true&visual=true"
        },
        thumbnail_hosts: [ /\Ai\d*\.sndcdn\.com\z/ ],
        allow: "autoplay"
      ),
      Provider.new(
        key: "vimeo", label: "Vimeo",
        hosts: %w[vimeo.com www.vimeo.com],
        media_id: lambda { |uri|
          video, unlisted = uri.path.match(VIMEO_PATH)&.captures
          [ video, unlisted ].compact.join("/") if video
        },
        canonical: ->(id) { "https://vimeo.com/#{id}" },
        oembed: "https://vimeo.com/api/oembed.json",
        # dnt=1 asks the player not to track the session or set cookies.
        player: lambda { |id|
          video, unlisted = id.split("/")
          "https://player.vimeo.com/video/#{video}?dnt=1&autoplay=1#{"&h=#{unlisted}" if unlisted}"
        },
        thumbnail_hosts: %w[i.vimeocdn.com],
        allow: "autoplay; fullscreen; picture-in-picture"
      ),
      Provider.new(
        key: "spotify", label: "Spotify",
        hosts: %w[open.spotify.com],
        media_id: lambda { |uri|
          kind, id = uri.path.match(SPOTIFY_PATH)&.captures
          "#{kind}/#{id}" if kind
        },
        canonical: ->(id) { "https://open.spotify.com/#{id}" },
        oembed: "https://open.spotify.com/oembed",
        player: ->(id) { "https://open.spotify.com/embed/#{id}" },
        thumbnail_hosts: [ "i.scdn.co", /\Aimage-cdn-[a-z]+\.spotifycdn\.com\z/ ],
        allow: "autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture"
      ),
      # A whyp.it share link names the track and, for a private upload, the
      # share token that opens it; the player takes the same two. The oEmbed
      # answer names its player by a different id, which is ignored like the
      # rest of its markup.
      Provider.new(
        key: "whyp", label: "Whyp",
        hosts: %w[whyp.it www.whyp.it],
        media_id: lambda { |uri|
          track = uri.path[WHYP_PATH, 1]
          token = URI.decode_www_form(uri.query.to_s).to_h["token"]
          next unless track
          next track unless token
          "#{track}/#{token}" if token.match?(WHYP_TOKEN)
        },
        canonical: lambda { |id|
          track, token = id.split("/")
          "https://whyp.it/tracks/#{track}#{"?token=#{token}" if token}"
        },
        oembed: "https://api.whyp.it/api/oembed",
        player: lambda { |id|
          track, token = id.split("/")
          "https://whyp.it/embeds/track/#{track}#{"?token=#{token}" if token}"
        },
        thumbnail_hosts: %w[cdn.whyp.it],
        allow: "autoplay"
      ),
    ].freeze

    # Links in prose or in the HTML a rich-text editor writes; a quote or an
    # angle bracket ends one either way.
    URL = %r{https?://[^\s<>"']+}
    TRAILING_PUNCTUATION = /[.,;:!?)\]]+\z/
    OEMBED_MAX_BODY = 100_000
    THUMBNAIL_MAX_BODY = OutboundHttp::MAX_MEDIA_BODY
    # Only these image types enter the cache, and the extension the cache file
    # carries is what the serving controller declares as its content type.
    THUMBNAIL_TYPES = {
      "image/jpeg" => ".jpg", "image/png" => ".png",
      "image/webp" => ".webp", "image/gif" => ".gif",
    }.freeze
    THUMBNAIL_USER_AGENT = "pub5 link embed thumbnail"
    DEMO = File.expand_path("../../../config/demo_link_embeds.yml", __dir__)
    USER_AGENT = "pub5 link embed"

    module_function

    # The first link in the text that a provider recognises, or nil.
    def find(text)
      CGI.unescapeHTML(text.to_s).scan(URL).each do |raw|
        match = match_url(raw.sub(TRAILING_PUNCTUATION, ""))
        return match if match
      end
      nil
    end

    def match_url(url)
      uri = URI.parse(url)
      return unless uri.is_a?(URI::HTTP) && uri.userinfo.nil? && uri.port == uri.default_port

      PROVIDERS.each do |provider|
        id = provider.match(uri)
        return Match.new(provider:, media_id: id, source_url: url) if id
      end
      nil
    rescue URI::InvalidURIError
      nil
    end

    # The seeders' posts for one app, each carrying the resolved embed of the
    # verified link its text names, so seeding asks no provider.
    def demo_posts(app, catalog: DEMO)
      catalog = YAML.safe_load_file(catalog)
      catalog.fetch("posts").fetch(app.to_s).map do |row|
        link = catalog.fetch("links").fetch(row.fetch("link"))
        match = find(row["content"] || row["body"])
        unless match&.source_url == link["source_url"]
          raise KeyError, "demo post #{row["link"]} does not carry #{link["source_url"]}"
        end

        embed = Record.new(match:, status: "ok", title: link["title"], author_name: link["author_name"],
                           thumbnail_url: link["thumbnail_url"], fetched_at: catalog.fetch("verified_on"))
        row.transform_keys(&:to_sym).merge(link_embed: embed.to_h)
      end
    end

    def resolve(match, fetch: method(:fetch_oembed), at: Time.now)
      Record.from_oembed(match, fetch.call(match.provider.oembed_uri(match.media_id)), at:)
    end

    # --- First-party thumbnail cache (shared-029) ---------------------------
    #
    # A facade's image used to load straight from the provider's CDN on every
    # page view — a contact the play-button facade promises never to make. The
    # image is now fetched once, where the oEmbed answer already arrives (the
    # job, the compose preview), written to this cache, and served from the
    # app's own /link_embeds/thumbnails/:digest endpoint afterwards. A page
    # view contacts no provider, and the stored record needs no new field: the
    # cache file is content-addressed by the digest of the provider URL.

    # The cache lives under storage/, beside the app's other runtime media.
    def thumbnail_cache_dir
      Rails.root.join("storage/link_embeds/thumbnails")
    end

    # 128 bits of the SHA-256 of the provider URL: the route fragment and the
    # cache filename, with no user input in the served path.
    def thumbnail_digest(url)
      Digest::SHA256.hexdigest(url.to_s)[0, 32]
    end

    # The provider's image bytes, or nil. Only the four web image types enter
    # the cache; anything else degrades to no image rather than to a file this
    # app would serve with a content type it has not decided on.
    def fetch_thumbnail(uri)
      response = Shared::OutboundHttp.request(
        uri,
        headers: { "Accept" => "image/*", "User-Agent" => THUMBNAIL_USER_AGENT },
        max_body: THUMBNAIL_MAX_BODY,
      )
      return unless response.is_a?(Net::HTTPSuccess)

      type = response.content_type.to_s.split(";").first.to_s.strip.downcase
      return unless THUMBNAIL_TYPES.key?(type)

      [response.body.to_s, type]
    end

    # Fetches and stores the thumbnail once. Returns truthy when the cache
    # holds the image after the call. A failed fetch is silent: the facade
    # degrades to no image, never to a provider contact on page view, and the
    # next refresh (the job, or the compose preview) tries again.
    def cache_thumbnail!(url, fetch: method(:fetch_thumbnail))
      return false unless url
      return true if thumbnail_cached?(url)

      fetched = fetch.call(URI(url))
      return false unless fetched

      body, type = fetched
      dir = thumbnail_cache_dir
      FileUtils.mkdir_p(dir)
      # Write beside the target and rename, so a concurrent reader never sees a
      # half-written image and two jobs racing land on one file.
      tmp = dir.join("#{thumbnail_digest(url)}.#{Process.pid}.tmp")
      tmp.write(body)
      File.rename(tmp, dir.join("#{thumbnail_digest(url)}#{THUMBNAIL_TYPES.fetch(type)}"))
      true
    rescue *OutboundHttp::NETWORK_ERRORS, IOError, SystemCallError => e
      Rails.logger.warn("link_embed: thumbnail fetch failed: #{e.class}") if defined?(Rails.logger)
      false
    end

    # The cache file for a digest, tmp particles excluded, or nil.
    def thumbnail_file(digest)
      return unless digest.to_s.match?(/\A[0-9a-f]{32}\z/)

      children = Dir.glob(thumbnail_cache_dir.join("#{digest}.*"))
      children.reject { |path| path.end_with?(".tmp") }.first
    end

    def thumbnail_cached?(url)
      !thumbnail_file(thumbnail_digest(url)).nil?
    end

    # For the serving controller: [path, content_type] or nil.
    def cached_thumbnail(digest)
      file = thumbnail_file(digest)
      return unless file

      type = THUMBNAIL_TYPES.key(file.extname)
      [file, type]
    end

    # The provider's description of the media, or nil when it would not give one.
    def fetch_oembed(uri)
      response = Shared::OutboundHttp.request(
        uri,
        headers: { "Accept" => "application/json", "User-Agent" => USER_AGENT },
        max_body: OEMBED_MAX_BODY,
      )
      return unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body.to_s)
      data if data.is_a?(Hash)
    rescue *Shared::OutboundHttp::NETWORK_ERRORS, JSON::ParserError => e
      Rails.logger.warn("link_embed: #{uri.host} failed: #{e.class}") if defined?(Rails.logger)
      nil
    end
  end
end
