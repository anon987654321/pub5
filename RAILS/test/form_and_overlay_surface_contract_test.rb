# frozen_string_literal: true

require "minitest/autorun"

class FormAndOverlaySurfaceContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CSS = %w[
    components/_forms.scss
    components/_overlays.scss
    components/_fields.scss
  ].map { |path| File.read(File.join(ROOT, "__shared/app/assets/stylesheets", path)) }.join("\n")
  HOOK = File.read(File.expand_path("../../.githooks/pre-push", __dir__))

  def test_text_controls_have_a_shared_surface_and_focus_state
    assert_includes CSS, 'input[type="datetime-local"]'
    assert_includes CSS, "min-block-size: max(var(--tap-min), 3rem)"
    assert_includes CSS, "border: 1px solid var(--border)"
    assert_includes CSS, "border-color: var(--accent)"
    # Fields pair a persistent boundary with the shared keyboard focus ring.
    assert_match(/\):not\(\.button\):focus-visible \{[^}]*outline: var\(--focus-ring\);/m, CSS)
    assert_includes CSS, ":not(.button):user-invalid"
  end

  def test_default_submit_is_phone_width_without_becoming_a_desktop_bar
    assert_includes CSS, "inline-size: 100%"
    assert_includes CSS, "@media (min-width: 480px)"
    assert_includes CSS, "min-inline-size: max(10rem, var(--tap-min))"
  end

  def test_unclassified_submit_controls_cannot_fall_back_to_ua_buttons
    assert_includes CSS, 'input[type="submit"]:not(.button):not([class])'
    assert_includes CSS, 'button[type="submit"]:not(.button):not([class])'
  end

  def test_native_dialog_and_popover_have_shared_tokens
    assert_includes CSS, "dialog::backdrop"
    assert_includes CSS, "[popover]"
    assert_includes CSS, "max-block-size: calc(100dvh"
    assert_includes CSS, "var(--scrim)"
  end

  def test_pre_push_regenerates_snapshots_before_publishing
    assert_includes HOOK, "\"tools\", \"snapshot.rb\""
    assert_includes HOOK, "snapshot regeneration failed; push refused"
  end
end
