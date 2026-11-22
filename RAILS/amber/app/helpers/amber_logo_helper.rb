# frozen_string_literal: true

# Alternative Amber marks: the study plates that passed review, installed as
# propshaft assets (app/assets/images/amber). The canonical inline partial in
# app/views/shared/_logo.html.erb stays the default mark; a variant swaps the
# nav/home logo only when configuration asks for it, so a deploy can dress the
# shop in one of the approved directions without touching the artwork itself.
module AmberLogoHelper
  # Key -> propshaft asset under app/assets/images/amber. The SVGs are byte
  # copies of the reviewed plates in __logo/plates; the contract test keeps
  # the two from drifting.
  VARIANT_ASSETS = {
    "dither4-press" => "amber/dither4-press.svg",
    "signal-orbit" => "amber/signal-orbit.svg",
    "hue-flow" => "amber/hue-flow.svg",
    "starlight" => "amber/starlight.svg",
    "grade-teal-amber" => "amber/grade-teal-amber.svg",
    "reference" => "amber/reference.svg",
  }.freeze

  # Set AMBER_LOGO_VARIANT in the environment (or Rails.application.config.x)
  # to a key above; anything else keeps the canonical inline mark.
  def amber_logo_variant
    Rails.configuration.x.amber_logo_variant.to_s.strip.presence
  end

  def amber_variant_logo_asset(variant)
    VARIANT_ASSETS[variant.to_s]
  end

  def amber_variant_logo_tag(variant)
    asset = amber_variant_logo_asset(variant)
    return unless asset

    image_tag(asset, class: "amber-variant-logo",
                     alt: t("amber.logo_aria"),
                     aria: { hidden: false })
  end
end
