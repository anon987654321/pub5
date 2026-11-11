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

    assert_includes first, "a-text-mask"
    assert_includes first, "a-caprasimo-a"
    assert_includes second, "b-text-mask"
    assert_includes second, "b-caprasimo-a"
  end

  test "chrome uses the amber mark, not the shared brgen wordmark" do
    layout = Rails.root.join("app/views/layouts/application.html.erb").read

    assert_includes layout, 'render "shared/logo"'
    refute_match(%r{render ["']shared/brand_mark["']}, layout)
  end

  test "pixel-anime decorations are isolated from the canonical logo" do
    layout = Rails.root.join("app/views/layouts/application.html.erb").read
    logo = Rails.root.join("app/views/shared/_logo.html.erb").read
    css = Rails.root.join("app/assets/stylesheets/application.scss").read

    assert_includes layout, 'class="amber-magic-layer" aria-hidden="true"'
    assert_operator layout.index('class="amber-magic-layer"'), :<,
                    layout.index('class: "amber-logo-home"')
    assert_includes layout, 'if home'
    assert_includes css, ".amber-magic-layer"
    assert_includes css, "pointer-events: none"
    assert_includes css, "@media (prefers-reduced-motion: reduce)"
    # The decorations must never become part of, or style, the canonical SVG.
    refute_includes logo, "amber-magic"
    refute_match(/\.amber-magic[^}]*\.amber-logo-svg/m, css)
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
  test "logo study plates preserve the canonical white swoosh geometry" do
    source = Rails.root.join("app/views/shared/_logo.html.erb").read
    canonical = source.scan(/<path stroke="#FFFFFF" stroke-width="([\d.]+)" stroke-opacity="1\.0" fill="none" d="([^"]+)"\/>/)

    assert_equal 9, canonical.size
    plates = Dir.glob(Rails.root.join("__logo/plates/[0-9][0-9]_*.svg").to_s)
    assert_equal 10, plates.size

    plates.each do |path|
      svg = File.read(path)
      number = File.basename(path)[0, 2].to_i
      actual = svg.scan(/<path stroke="#FFFFFF" stroke-width="([\d.]+)" stroke-opacity="1\.0" fill="none" d="([^"]+)"\/>/)
      first_line = svg.index('<path stroke="#FFFFFF"')
      line_group = svg.rindex(%(<g clip-path="url(#pl#{number}-text)">), first_line)
      group_end = svg.index("</g>", first_line)

      assert_equal canonical, actual, "#{path} changed the source swoosh"
      assert line_group && line_group < first_line && first_line < group_end,
             "#{path} lets the study swoosh escape its glyph clip"
    end
  end

  test "production logo reference keeps the full-width swoosh outside the ink clip" do
    source = Rails.root.join("app/views/shared/_logo.html.erb").read
    canonical = source.scan(/<path stroke="#FFFFFF" stroke-width="([\d.]+)" stroke-opacity="1\.0" fill="none" d="([^"]+)"\/>/)
    reference = Rails.root.join("__logo/plates/reference-original.svg").read

    assert_includes reference, 'viewBox="0 0 1000 500"'
    assert_equal canonical, reference.scan(/<path stroke="#FFFFFF" stroke-width="([\d.]+)" stroke-opacity="1\.0" fill="none" d="([^"]+)"\/>/)
    assert_equal 1, reference.scan('<g clip-path="url(#pl0-text)">').size
    assert_operator reference.index("</g>"), :<, reference.index('<path stroke="#FFFFFF"')
  end

  test "logo study avatars remain transparent and preserve the canonical swoosh" do
    source = Rails.root.join("app/views/shared/_logo.html.erb").read
    canonical = source.scan(/<path stroke="#FFFFFF" stroke-width="([\d.]+)" stroke-opacity="1\.0" fill="none" d="([^"]+)"\/>/)
    avatars = Dir.glob(Rails.root.join("__logo/plates/avatars/*.svg").to_s)

    assert_equal 3, avatars.size
    avatars.each do |path|
      svg = File.read(path)
      assert_equal canonical, svg.scan(/<path stroke="#FFFFFF" stroke-width="([\d.]+)" stroke-opacity="1\.0" fill="none" d="([^"]+)"\/>/)
      refute_includes svg, 'fill="#0B0B0B"', "avatar exports must not include a solid ground"
    end
  end

  test "logo study generator reads the live partial and clears old plates before generation" do
    generator = Rails.root.join("__logo/generate.mjs").read

    assert_includes generator, 'const ROOT = join(DIR, "../../..");'
    assert_includes generator, 'RAILS/amber/app/views/shared/_logo.html.erb'
    assert_includes generator, "function canonicalHairlines()"
    assert_includes generator, 'for (const f of readdirSync(OUT)) rmSync(join(OUT, f), { recursive: true });'
    refute_includes generator, "steppedLine"
    refute_includes generator, "pony_rainbow"
    refute_includes generator, "starlight_comet"
    refute_includes generator, "stepped swoosh"
    refute_includes generator, "roams behind the letters"
    refute_includes generator, "tail7"
  end
  test "GLM logo renders are installed as app-owned public assets" do
    root = Rails.root.join("public")
    %w[
      amber-logo-dither4-press.png
      amber-logo-signal-orbit.png
      amber-logo-hue-flow.png
      amber-logo-starlight.png
      amber-logo-grade-teal-amber.png
      amber-logo-avatar-bit8.png
      amber-logo-avatar-candy.png
      amber-logo-avatar-canon.png
      amber-logo-bit8-pixel-ink.png
      amber-logo-reference.png
    ].each do |name|
      path = root.join(name)
      assert File.file?(path), "missing generated logo asset: #{name}"
      assert File.size?(path).to_i.positive?, "empty generated logo asset: #{name}"
    end
  end

  test "logo study gallery paths and plate descriptions stay in sync" do
    root = Rails.root.join("__logo")
    html = root.join("all-plates.html").read
    images = html.scan(/<img\b[^>]*\bsrc="([^"]+)"/).flatten

    assert_equal 20, images.size
    images.each do |asset|
      assert File.file?(root.join(asset)), "missing gallery asset: #{asset}"
    end

    assert_includes html, "07 · starlight — night-sky ink and stars inside the glyphs"
    refute_includes html, "starlight comet"
    assert_includes html, "@media (max-width: 700px)"

    pixel = File.read(root.join("plates/02_bit8_pixel.svg"))
    assert_includes pixel, "the original white swoosh"
    refute_includes pixel, "stepped swoosh"

    signal_orbit = File.read(root.join("plates/04_signal_orbit.svg"))
    assert_includes signal_orbit, "the radial ink roams inside the letters"
    refute_includes signal_orbit, "behind the letters"

    starlight = File.read(root.join("plates/07_starlight.svg"))
    assert_includes starlight, "original white swoosh unchanged"
    refute_includes starlight, "tail7"

    generator = root.join("generate.mjs").read
    assert_includes generator, "@media (max-width: 700px)"
  end

end
