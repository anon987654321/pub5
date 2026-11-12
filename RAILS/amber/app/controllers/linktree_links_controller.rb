# frozen_string_literal: true

# One click on a public link-in-bio page: count it, then send the visitor on
# their way. An internal link lands on the gated surface, where its own
# checks take over; an external link is a plain redirect.
class LinktreeLinksController < ApplicationController
  def show
    link = LinktreeLink.find(params[:id])
    destination = link.destination_path
    return redirect_to link.linktree_page, alert: t("flash.linktree_link_unavailable") if destination.blank?

    LinktreeEvent.create!(
      linktree_page: link.linktree_page, linktree_link: link, event_type: "link_click",
      visitor_hash: LinktreeEvent.visitor_hash(request),
    )
    redirect_to destination, allow_other_host: link.external?
  end
end
