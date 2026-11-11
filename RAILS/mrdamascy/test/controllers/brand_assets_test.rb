# frozen_string_literal: true

require "test_helper"

# The brand bar draws public/logo.svg on every page.
class BrandAssetsTest < ActiveSupport::TestCase
  test "the logo stays light and keeps its drawing" do
    logo = Rails.public_path.join("logo.svg").read

    assert_operator logo.bytesize, :<, 25_000, "logo.svg has grown back past 25 KB"
    assert_includes logo, %(viewBox="0 0 3527 971")
    assert_equal 35, logo.scan("<path").size
    assert_no_match(/\d\.\d/, logo[/ d="[^"]*"/], "path data keeps whole viewBox units")
  end

  test "the brand bar shows the full original vector without cropping" do
    layout = Rails.root.join("app/views/layouts/application.html.erb").read
    base = Rails.root.join("app/assets/stylesheets/_base.scss").read

    assert_includes layout, 'image_tag "/logo.svg"'
    assert_match(/\.brand-logo\s*\{[^}]*height:\s*32px;[^}]*width:\s*auto;[^}]*object-fit:\s*contain;/m, base)
    assert_includes base, "object-position: left center"
  end

  test "the original wordmark is blended into the brand bar without editing the asset" do
    logo = Rails.public_path.join("logo.svg").read
    tokens = Rails.root.join("app/assets/stylesheets/_tokens.scss").read
    base = Rails.root.join("app/assets/stylesheets/_base.scss").read

    assert_includes logo, 'fill="#434244"'
    assert_match(/--brand-charcoal:\s*#434244;/, tokens)
    assert_match(/\.brand-bar\s*\{[^}]*background:\s*var\(--brand-charcoal\)/m, base)
    assert_match(/\.brand-link\s*\{[^}]*color:\s*var\(--paper\)/m, base)
  end
end
