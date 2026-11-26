# frozen_string_literal: true

module Shared
  # Include in a SitemapsController and implement #sitemap_entries to return
  # an array of Shared::SitemapBuilder::Entry — the XML rendering is shared.
  #
  # Every crawler of a host gets the same answer until its data moves, so the
  # rendered XML is cached per host (a sitemap may only carry its own host's
  # URLs). Caching only the entries, as each app did, still rebuilt 1.5 MB of
  # XML per hit: bsdports.org/sitemap.xml took 7-10s warm on 2026-11-26.
  # An app whose data moves faster overrides #sitemap_ttl.
  module Sitemapable
    extend ActiveSupport::Concern

    def index
      xml = Rails.cache.fetch("sitemap/xml/#{request.host}", expires_in: sitemap_ttl) do
        Shared::SitemapBuilder.render(sitemap_entries)
      end
      render xml:
    end

    private

    def sitemap_ttl = 1.hour
  end
end
