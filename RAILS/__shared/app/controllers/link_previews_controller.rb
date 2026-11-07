# frozen_string_literal: true

# The player a pasted link will become, shown while the post is still being
# written, the way the first brgen previewed links under its compose form.
#
# Only a link a Shared::LinkEmbed provider recognises gets an answer, and the
# one request goes to that provider's oEmbed endpoint: the pasted URL itself is
# never fetched. Answers are cached by the link they name, and the endpoint is
# rate-limited, so typing does not turn into a request per keystroke upstream.
#
# The thumbnail action serves the facade's image from the app's own cache
# (shared-029): the provider is contacted where the oEmbed answer arrives, and
# the page view loads the image from here. The digest is the SHA-256 of the
# provider URL — hex-validated by the route constraint and by the lookup, so no
# request parameter ever reaches a file path.
class LinkPreviewsController < ApplicationController
  URL_MAX = 2_048
  THUMBNAIL_DIGEST = /\A[0-9a-f]{32}\z/

  allow_unauthenticated_access only: %i[show thumbnail] if respond_to?(:allow_unauthenticated_access)
  rate_limit to: 30, within: 1.minute, only: :show if respond_to?(:rate_limit)

  def show
    match = Shared::LinkEmbed.find(params[:url].to_s[0, URL_MAX])
    return head :no_content unless match

    stored = Rails.cache.fetch([ "link_preview", match.canonical_url ], expires_in: 12.hours) do
      fresh = Shared::LinkEmbed.resolve(match)
      # The one place a page-triggered fetch may touch the provider's image
      # host: the compose preview is the moment the reader asks for the embed.
      Shared::LinkEmbed.cache_thumbnail!(fresh.thumbnail_url) if fresh.ok?
      fresh.to_h
    end
    embed = Shared::LinkEmbed::Record.from_stored(stored)
    return head :no_content unless embed&.ok?

    render partial: "shared/link_embed", locals: { embed: }
  end

  def thumbnail
    found = Shared::LinkEmbed.cached_thumbnail(params[:digest].to_s)
    return head :not_found unless found

    # Digest-addressed content: the bytes never change under a URL, so the
    # browser can hold it for a year.
    expires_in 1.year, public: true
    send_file found.first, type: found.last, disposition: "inline"
  end
end
