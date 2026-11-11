# frozen_string_literal: true

require "test_helper"

# The city wordmark must land in exactly the same place on every brgen surface.
# It did not: playlist overrode top, inset-inline-start, padding, min-height,
# min-width and font-size, putting the mark at (6, 4) 53x23 against (14, 9)
# 63x44 everywhere else — a visible jump when moving between verticals.
#
# Asserted against the stylesheet rather than a rendered page because the
# offending rules were body.vertical-* overrides, and a request spec only ever
# exercises one surface at a time.
class LogoPlacementTest < ActiveSupport::TestCase
  STYLESHEETS = Rails.root.glob("app/assets/stylesheets/*.scss").freeze

  # Anything that moves or resizes the mark. Colour and z-index are fine: a
  # vertical may need to win a stacking contest or invert on its own backdrop.
  PLACEMENT = %w[
    top bottom left right inset inset-block-start inset-inline-start
    padding margin min-height min-width width height
    font-size font-weight letter-spacing position transform
  ].freeze

  def logo_override_declarations
    STYLESHEETS.flat_map do |path|
      source = path.read
      # body.vertical-x .brgen-logo-mark { ... } — the surface-scoped ones only.
      source.scan(/^\s*body\.vertical-[\w-]+[^{]*\.brgen-logo-mark[^{]*\{([^}]*)\}/m).flat_map do |(body)|
        body.scan(/^\s*([a-z-]+)\s*:/).flatten.map { |prop| [ path.basename.to_s, prop ] }
      end
    end
  end

  def test_no_vertical_moves_or_resizes_the_wordmark
    offenders = logo_override_declarations.select { |(_file, prop)| PLACEMENT.include?(prop) }

    assert_empty offenders.map { |file, prop| "#{file}: #{prop}" },
                 "the wordmark must sit in the same spot on every surface"
  end

  # The layout renders it once, unconditionally, outside any vertical guard —
  # so every surface gets one and only one.
  #
  # Asserted through the shared partial rather than the class literal. The mark
  # moved into shared/_brand_mark so brgen, amber and bsdports render the same
  # one: brgen had a fixed wordmark, amber a non-fixed SVG, bsdports none at all
  # (and, once counted, three separate links home). brgen still passes
  # .brgen-logo-mark alongside .brand-mark, so every rule already written against
  # it keeps applying — but the class name is now an argument, not markup, and a
  # test that greps for the literal was testing the spelling.
  def test_layout_renders_exactly_one_wordmark
    layout = Rails.root.join("app/views/layouts/application.html.erb").read

    assert_equal 1, layout.scan(%r{render "shared/brand_mark"}).size
    assert_includes layout, "brgen-logo-mark"
  end

  # Unconditional: no vertical, auth or guest branch may skip it.
  def test_the_wordmark_is_not_behind_a_conditional
    layout = Rails.root.join("app/views/layouts/application.html.erb").read
    line = layout.lines.find { |l| l.include?('render "shared/brand_mark"') }

    refute_nil line
    refute_match(/\bif\b|\bunless\b/, line,
                 "the mark must render on every surface, not behind a guard")
  end

  def test_marketplace_keeps_its_original_face_and_cart_with_a_bounded_burst
    logo = Rails.root.join("engines/marketplace/app/views/marketplace/_animated_logo.html.erb").read
    controller = Rails.root.join("engines/marketplace/app/javascript/controllers/marketplace_logo_controller.js").read

    assert_includes logo, 'id="marketplace-logo-a"'
    assert_includes logo, 'id="marketplace-logo-j"'
    assert_equal 8, logo.scan('data-marketplace-logo-target="smileyPath"').size
    assert_equal 2, logo.scan('data-marketplace-logo-target="cartPath"').size
    assert_includes controller, "i <= 16"
    assert_includes controller, "data-marketplace-logo-particle"
    assert_includes controller, "connectionToken !== this.connectionToken"
    assert_includes controller, "targets: particles"
    refute_includes controller, 'querySelectorAll(":scope > span")'
    assert_includes controller, "particles.forEach((particle) => particle.remove())"
    assert_includes controller, 'if (window.matchMedia("(prefers-reduced-motion: reduce)").matches)'
    assert_includes controller, "this.#staticEndState()"
  end

  def test_dating_reuses_the_historical_hjerterom_heart
    splash = Rails.root.join("engines/dating/app/views/dating/home/splash.html.erb").read
    logo = Rails.root.join("engines/dating/app/views/dating/home/_hjerterom_logo.html.erb").read
    controller = Rails.root.join("engines/dating/app/javascript/controllers/dating_splash_controller.js").read
    stylesheet = Rails.root.join("app/assets/stylesheets/_brgen_dating.scss").read

    assert_includes splash, 'render "dating/home/hjerterom_logo"'
    assert_includes splash, 'label: "Hjerterom"'
    refute_includes splash, "compact: true"
    refute_includes splash, "<css-doodle"
    refute_includes splash, "dating-splash-heart-path"

    # Provenance and geometry are pinned to the old Hjerterom partial in pub4.
    assert_includes logo, "0f586be5715f91b15ce3b0f0621506726ccef4e2"
    assert_includes logo, 'M100,26.79625 c-4.9725,-13.4975,-30,-11.4925'
    assert_includes logo, 'fill="#DC143C"'
    assert_includes logo, 'id="heartClip-<%= svg_uid %>"'
    assert_equal 14, logo.scan("<path ").size
    assert_equal 60, logo.scan(/<animate(?:Transform)?\b/).size
    assert_includes logo, 'data-dating-splash-target="hjerterom"'

    # Reduced motion pauses the original SMIL artwork at its initial frame;
    # changing the preference back resumes it without another logo asset.
    assert_includes controller, 'window.matchMedia("(prefers-reduced-motion: reduce)")'
    assert_includes controller, "setCurrentTime?.(0)"
    assert_includes controller, "pauseAnimations?.()"
    assert_includes controller, "unpauseAnimations?.()"
    assert_includes controller, 'addEventListener("change"'
    assert_includes controller, "removeEventListener"

    assert_includes logo, "<%= label.downcase %>"
    assert_includes stylesheet, ".dating-hjerterom-logo"
    assert_includes stylesheet, "aspect-ratio: 4 / 3"
    assert_includes stylesheet, "fill: currentColor"
  end

  def test_playlist_tunnel_has_its_own_decorative_wave_mark
    tunnel = Rails.root.join("engines/radio/playlist/app/views/playlist/playlists/_radio_tunnel.html.erb").read
    stylesheet = Rails.root.join("app/assets/stylesheets/_brgen_vertical_surfaces.scss").read

    assert_includes tunnel, '<svg class="radio-brand-mark"'
    assert_includes tunnel, 'aria-hidden="true" focusable="false"'
    assert_match(/radio-now-playing.*radio-brand-mark.*radio-track-display/m, tunnel)
    refute_includes tunnel, '<header class="radio-header">'
    assert_includes stylesheet, ".radio-brand-mark"
    assert_includes stylesheet, "color: var(--color-accent)"
    refute_includes stylesheet, ".radio-header h1"
  end
end
