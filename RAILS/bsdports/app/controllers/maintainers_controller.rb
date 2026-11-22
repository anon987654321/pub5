# frozen_string_literal: true

class MaintainersController < ApplicationController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]

  def index
    scope = Maintainer.order(:name)
    scope = apply_live_search(scope, columns: %w[name email], vertical: "maintainers") if live_search_query.present?
    @pagy, @maintainers = pagy(scope)
    # One grouped COUNT for the page; historical package rows are not current catalogue entries.
    @port_counts = Port.available.where(maintainer_id: @maintainers.map(&:id)).group(:maintainer_id).count
    finish_live_search(partial: "maintainers/live_search_results")
  end

  def show
    @maintainer = Maintainer.find(params[:id])
    @maintainer.record_activity!("MaintainerViewed", source_vertical: "bsdports") unless passive_request?
    # The page is the maintainer and a page of ports; an import that changes
    # either moves one of these. The page number lives in the URL, and :usec
    # keeps a same-second import from expanding to an unchanged key.
    return unless stale?(etag: [
      @maintainer.cache_key_with_version,
      @maintainer.ports.available.maximum(:updated_at)&.to_fs(:usec), @maintainer.ports.available.count
    ])

    @pagy, @ports = pagy(@maintainer.ports.available.order(:name))
  end
end
