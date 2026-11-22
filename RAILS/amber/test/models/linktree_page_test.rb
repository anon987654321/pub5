# frozen_string_literal: true

require "test_helper"

# The link-in-bio surface: a public page for a creator, links that point out
# or in, and the two events worth counting. An internal link routes to the
# gated surface; the paywall behind it is never the page's to weaken.
class LinktreePageTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email_address: "lt-#{SecureRandom.hex(4)}@example.no", password: "password123")
    @creator = CreatorProfile.create!(user: @user, handle: "ragnhild",
                                      display_name: "Ragnhild", bio: "<p>taste with evidence</p>")
    @page = LinktreePage.create!(creator_profile: @creator, slug: "ragnhild")
  end

  test "the slug is the identity, lowercase with dashes" do
    assert_equal "ragnhild", @page.to_param
    assert_raises(ActiveRecord::RecordInvalid) do
      LinktreePage.create!(creator_profile: @creator, slug: "Ragnhild!")
    end
  end

  test "an internal link routes into the gated surface" do
    post = @user.posts.create!(body: "the look", price_minor: 1900, currency: "NOK")
    link = LinktreeLink.create!(linktree_page: @page, title: "My new look", linkable: post)

    assert_predicate link, :internal?
    assert_equal "/posts/#{post.id}", link.destination_path
  end

  test "an external link is the stored URL" do
    link = LinktreeLink.create!(linktree_page: @page, title: "Instagram",
                                url: "https://instagram.com/ragnhild")

    refute_predicate link, :internal?
    assert_equal "https://instagram.com/ragnhild", link.destination_path
  end

  test "a link with neither a url nor a linkable routes nowhere" do
    link = LinktreeLink.create!(linktree_page: @page, title: "broken")

    assert_nil link.destination_path
  end

  test "hidden links stay on the page but out of the list" do
    shown = LinktreeLink.create!(linktree_page: @page, title: "shown")
    LinktreeLink.create!(linktree_page: @page, title: "hidden", visible: false)

    assert_includes @page.linktree_links.visible, shown
    assert_equal 1, @page.linktree_links.visible.count
  end

  test "views and clicks count with an anonymized visitor" do
    request = ActionDispatch::TestRequest.create(remote_addr: "203.0.113.9", user_agent: "test/1.0")
    hash = LinktreeEvent.visitor_hash(request)

    LinktreeEvent.create!(linktree_page: @page, event_type: "page_view", visitor_hash: hash)
    LinktreeEvent.create!(linktree_page: @page, event_type: "link_click", visitor_hash: hash,
                          linktree_link: LinktreeLink.create!(linktree_page: @page, title: "x"))

    assert_equal 1, @page.linktree_events.views.count
    assert_equal 1, @page.linktree_events.clicks.count
    assert_match(/\A[0-9a-f]{64}\z/, hash)
  end
end
