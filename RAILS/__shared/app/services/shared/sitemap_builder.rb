# frozen_string_literal: true

require "erb"

module Shared
  # Renders a sitemaps.org urlset from plain entries — one XML writer shared
  # by every app instead of each hand-rolling its own escaping/formatting.
  #
  # Plain string building with every value escaped: Builder::XmlMarkup took
  # 0.4s for 14k entries on the workstation and several seconds on vm23's one
  # vCPU, against 0.006s for this (2026-11-26).
  class SitemapBuilder
    Entry = Data.define(:loc, :lastmod, :changefreq, :priority) do
      def initialize(loc:, lastmod: nil, changefreq: nil, priority: nil)
        super
      end
    end

    HEAD = %(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)

    def self.render(entries)
      new(entries).render
    end

    def initialize(entries)
      @entries = entries
    end

    def render
      xml = +HEAD
      @entries.each { |entry| xml << url(entry) }
      xml << "</urlset>\n"
    end

    private

    def url(entry)
      fields = { loc: entry.loc, lastmod: entry.lastmod&.iso8601, changefreq: entry.changefreq,
                 priority: entry.priority }
      body = fields.filter_map { |tag, value| "<#{tag}>#{ERB::Util.html_escape(value)}</#{tag}>" unless value.nil? }
      "<url>#{body.join}</url>\n"
    end
  end
end
