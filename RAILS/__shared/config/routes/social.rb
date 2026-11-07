# frozen_string_literal: true

resources :notifications, only: %i[index update destroy] do
  collection do
    patch :read_all
    get :badge
  end
end
resources :reactions, only: :create
resources :reports, only: :create
# The player a link in an unfinished post will become (LinkPreviewsController).
get "link_previews", to: "link_previews#show", as: :link_preview
# The facade's thumbnail, from the app's own cache (shared-029). The digest is
# the SHA-256 of the provider URL the stored record names; a page view loads
# the provider image from here, never from the provider.
get "link_embeds/thumbnails/:digest", to: "link_previews#thumbnail",
    as: :link_embed_thumbnail, constraints: { digest: /\A[0-9a-f]{32}\z/ }

# Outbound affiliate/partner clicks. A beacon, not a redirect: this endpoint never
# receives a URL it will send anyone to, so it cannot become an open redirect, and
# the anchor keeps the merchant URL so the Link Converter script can still rewrite
# it. See Shared::OutboundClicksController.
resources :outbound_clicks, only: :create
