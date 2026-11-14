# frozen_string_literal: true

# The global search page's per-section navigation and matched-text presentation.
module SearchHelper
  SNIPPET_RADIUS = 80
  SNIPPET_LENGTH = 160

  # Sections searched on the city host itself: the index route that takes ?q=.
  APEX_SEARCHES = { posts: :posts_path, events: :events_path, communities: :communities_path }.freeze

  # Sections searched on a vertical's subdomain: route proxy, index route, and
  # subdomain (nil for the city's marketplace subdomain). Videos open TV's
  # channel search, which matches video titles too.
  VERTICAL_SEARCHES = {
    listings: [ :marketplace, :listings_url, nil ],
    restaurants: [ :marketplace_food, :restaurants_url, nil ],
    channels: [ :tv, :channels_url, "tv" ],
    videos: [ :tv, :channels_url, "tv" ],
    sets: [ :playlist, :sets_url, "playlist" ],
    places: [ :maps, :places_url, "maps" ],
  }.freeze

  # The section's own search, carrying the query, or nil for a section with no
  # search page of its own (people).
  def search_section_href(vertical, query)
    key = vertical.to_sym
    return main_app.public_send(APEX_SEARCHES[key], q: query) if APEX_SEARCHES.key?(key)

    proxy, route, subdomain = VERTICAL_SEARCHES[key]
    return unless proxy

    domain = Current.domain.presence || request.host
    public_send(proxy).public_send(route, q: query, host: domain, subdomain: subdomain || marketplace_subdomain)
  end

  # Mark the query consistently in result labels and excerpts.
  def search_highlight(text, query)
    highlight(text.to_s, query, highlighter: '<mark>\1</mark>')
  end

  # The post's text around the first match. A post found by its title alone
  # shows the opening instead, so every row reads the same.
  def search_snippet(text, query)
    plain = strip_tags(text.to_s).squish
    return if plain.blank?

    shown = excerpt(plain, query, radius: SNIPPET_RADIUS) || truncate(plain, length: SNIPPET_LENGTH)
    search_highlight(shown, query)
  end
end
