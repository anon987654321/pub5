# frozen_string_literal: true

# A creator's public link-in-bio page, at /@handle or /linktree/:slug. No
# sign-in: the page is the top of the funnel. The visit is counted as a
# page_view with an anonymized visitor hash; nothing here identifies a
# person.
class LinktreePagesController < ApplicationController
  def show
    page = LinktreePage.find_by(slug: params[:slug] || params[:id])
    return redirect_to root_path, alert: t("flash.linktree_not_found") if page.nil?

    @page = page
    @links = page.linktree_links.visible
    LinktreeEvent.create!(
      linktree_page: page, event_type: "page_view",
      visitor_hash: LinktreeEvent.visitor_hash(request), referrer: request.referer.to_s[0, 500],
    )
  end
end
