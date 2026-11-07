# frozen_string_literal: true

require "test_helper"

# Contract: Amber logo geometry and gradient match the canonical Caprasimo swoosh design.
# Since amber-057 the wordmark is outlined SVG paths: the real Caprasimo glyph
# outlines for "amber®" at 120 viewBox units on the swoosh (startOffset 2%,
# letter-spacing -3, the registered mark a 24-unit tspan at dx=10 dy=-40),
# verified pixel-equivalent against the browser's own text rendering in
# headless Chrome before the change landed. No webfont is fetched for the mark.
class LogoContractTest < ActionView::TestCase
  test "logo partial matches canonical swoosh path and white hairlines" do
    render partial: "shared/logo", locals: { id_prefix: "test" }
    html = rendered

    assert_includes html, 'viewBox="0 0 1000 500"'
    # Through the key, and now for both names. The <title> was asserted as the
    # English literal "Amber Logo - Nice Version" on the reasoning that it is an
    # internal name rather than chrome a screen reader reads. It is not
    # internal: SVG <title> is the accessible name whenever no aria-label wins,
    # it surfaces as a tooltip regardless, and "Nice Version" was never copy
    # anybody meant to ship. Both say the same thing through the same key, so
    # neither can drift into English on a Norwegian page.
    assert_equal 2, html.scan(I18n.t("amber.logo_aria")).size
    assert_includes html, 'd="M50,220 C250,180 750,180 950,220"'
    assert_includes html, "animated-gradient"
    assert_includes html, 'stroke="#FFFFFF"'
    assert_includes html, 'stroke-width="0.5"'
    assert_includes html, 'stroke-width="4"'
    assert_includes html, 'd="M50,238 C200,158 400,258 600,158 S850,218 950,188"'
  end

  test "the wordmark is outlined Caprasimo glyphs, not live text" do
    render partial: "shared/logo", locals: { id_prefix: "test" }
    html = rendered

    %w[a m b e r registered].each do |glyph|
      assert_includes html, "id=\"test-caprasimo-#{glyph}\"",
                      "the #{glyph} outline is missing from the clip"
      assert_includes html, "href=\"#test-caprasimo-#{glyph}\""
    end
    # Six glyph placements: a, m, b, e, r and the registered mark.
    assert_equal 6, html.scan("<use href=\"#test-caprasimo-").size
    # Live text would need the webfont; the outlined mark renders without it.
    refute_includes html, "<text"
    refute_includes html, "<textPath"
    refute_includes html, "font-family"
  end

  test "the wordmark needs no webfont anywhere" do
    render partial: "shared/logo", locals: { id_prefix: "test" }
    refute_includes rendered, "caprasimo-latin"

    layout = Rails.root.join("app/views/layouts/application.html.erb").read
    refute_match(%r{preload.*caprasimo}, layout,
                 "the layout preloads a webfont the outlined wordmark never reads")

    css = Rails.root.join("app/assets/stylesheets/application.scss").read
    refute_match(/@font-face[^}]*Caprasimo/m, css)
    refute_match(/\.amber-logo-svg \.amber-logo-word/, css)
  end

  test "logo uses unique ids per instance" do
    render partial: "shared/logo", locals: { id_prefix: "a" }
    first = rendered
    render partial: "shared/logo", locals: { id_prefix: "b" }
    second = rendered

    assert_includes first, "a-swoosh-path"
    assert_includes first, "a-text-mask"
    assert_includes first, "a-caprasimo-a"
    assert_includes second, "b-swoosh-path"
    assert_includes second, "b-text-mask"
    assert_includes second, "b-caprasimo-a"
  end

  test "chrome uses the amber mark, not the shared brgen wordmark" do
    layout = Rails.root.join("app/views/layouts/application.html.erb").read

    assert_includes layout, 'render "shared/logo"'
    refute_match(%r{render ["']shared/brand_mark["']}, layout)
  end

  test "public brand icons exist with amber palette" do
    root = Rails.root.join("public")
    %w[icon.svg icon.png icon-192.png apple-touch-icon.png favicon.ico].each do |name|
      path = root.join(name)
      assert File.file?(path), "missing #{name}"
      assert File.size?(path).to_i.positive?, "empty #{name}"
    end
    svg = File.read(root.join("icon.svg"))
    assert_includes svg, "#FFB999"
    assert_includes svg, "#99E6E6"
    assert_includes svg, "Amber"
  end
end
