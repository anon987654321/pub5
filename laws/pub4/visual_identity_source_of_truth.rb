# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/recovered_design_semantics.rb:55 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a141874c69d98a0f
require_relative "master/law/recovered_design_semantics"

Law.define(:VISUAL_IDENTITY_SOURCE_OF_TRUTH) do
  path "MASTER/data/tokens.yml"
  source "pub4 visual identity contract - canonical tokens, measured contrast and semantic face accent"
  scope :file
  detect do |text|
    document = YAML.safe_load(text, aliases: true)
    tokens = document.fetch("tokens")
    identity = tokens.fetch("visual_identity")
    anchors = tokens.fetch("face_root").fetch("anchors")
    signal = identity.fetch("signal")
    ink = identity.fetch("signal_ink")
    light_ink = identity.fetch("signal_on_light")
    fraction = Float(identity.fetch("max_highlight_area_fraction"))
    display_size = identity.fetch("display_size").to_s
    contrast_floors = identity.fetch("contrast")
    ink_floor = Float(contrast_floors.fetch("signal_on_ink_min"))
    white_floor = Float(contrast_floors.fetch("signal_on_white_min"))
    paper_floor = Float(contrast_floors.fetch("signal_on_paper_min"))
    motion = identity.fetch("motion")
    art_direction = identity.fetch("art_direction")
    typography_roles = identity.fetch("typography_roles")
    adaptations = identity.fetch("adaptations")
    avoid = identity.fetch("avoid")

    luminance = lambda do |hex|
      channels = hex.to_s.delete_prefix("#").scan(/../).map { |channel| channel.to_i(16) / 255.0 }
      next nil unless channels.length == 3

      linear = channels.map do |value|
        value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
      end
      0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    end
    contrast = lambda do |foreground, background|
      values = [luminance.call(foreground), luminance.call(background)]
      next 0.0 if values.any?(&:nil?)

      high, low = values.sort.reverse
      (high + 0.05) / (low + 0.05)
    end
    valid_hex = ->(value) { value.to_s.match?(/\A#[0-9a-f]{6}\z/i) }
    required_adapters = %w[master brgen amber bsdports openbsd studio]

    !identity.fetch("name").eql?("signal_and_stillness") ||
      !valid_hex.call(signal) || !valid_hex.call(ink) || !valid_hex.call(light_ink) ||
      !display_size.match?(/\Aclamp\([^)]*\)\z/) ||
      ink_floor < 7.0 || white_floor < 4.5 || paper_floor < 4.5 ||
      contrast.call(signal, ink) < ink_floor ||
      contrast.call(light_ink, "#FFFFFF") < white_floor ||
      contrast.call(light_ink, "#EFEFEF") < paper_floor ||
      fraction <= 0.0 || fraction > 0.08 ||
      anchors.fetch("c_accent") != "var(--pub4-signal)" ||
      motion.fetch("default") != "still" ||
      motion.fetch("change_requires_semantic_state") != true ||
      motion.fetch("reduced_motion_must_preserve_meaning") != true ||
      art_direction.fetch("subject_count").to_i != 1 ||
      art_direction.fetch("preserve_media_colour") != true ||
      art_direction.fetch("preserve_likeness") != true ||
      art_direction.fetch("grade_is_explicit") != true ||
      !art_direction.fetch("typography_layer").to_s.include?("editable") ||
      !art_direction.fetch("signal_usage").to_s.include?("never colour-grade") ||
      typography_roles.fetch("display") != "text-display" ||
      typography_roles.fetch("body") != "text-base" ||
      typography_roles.fetch("technical") != "font-mono" ||
      !typography_roles.fetch("wordmark").to_s.include?("original") ||
      !avoid.any? { |item| item.to_s.include?("protected brand expression") } ||
      !required_adapters.all? { |key| adaptations.fetch(key).is_a?(String) && !adaptations.fetch(key).empty? }
  rescue Psych::Exception, KeyError, TypeError, ArgumentError
    true
  end
  fix "Restore the canonical signal-and-stillness tokens, measured contrast, still-by-default motion, local dialect adapters and var(--pub4-signal) face anchor."
  bad <<~YAML
    tokens:
      visual_identity:
        name: signal_and_stillness
        signal: "#C8F55F"
        signal_ink: "#101010"
      face_root:
        anchors:
          c_accent: "#C8F55F"
  YAML
  good <<~YAML
    tokens:
      visual_identity:
        name: signal_and_stillness
        signal: "#C8F55F"
        signal_ink: "#101010"
        signal_on_light: "#50630A"
        display_size: "clamp(40px, 6vw, 88px)"
        contrast:
          signal_on_ink_min: 7.0
          signal_on_white_min: 4.5
          signal_on_paper_min: 4.5
        max_highlight_area_fraction: 0.08
        avoid: ["copied protected brand expression"]
        motion:
          default: still
          change_requires_semantic_state: true
          reduced_motion_must_preserve_meaning: true
        art_direction:
          subject_count: 1
          typography_layer: "separate and editable critical copy"
          signal_usage: "original graphics only; never colour-grade photographic subjects with the signal"
          preserve_media_colour: true
          preserve_likeness: true
          grade_is_explicit: true
        typography_roles:
          display: text-display
          body: text-base
          technical: font-mono
          wordmark: original pub4 artwork only
        adaptations:
          master: "signal on ink"
          brgen: "retain deep-blue identity"
          amber: "preserve garment colour"
          bsdports: "retain terminal green"
          openbsd: "plain operational text"
          studio: "operator-owned media grades"
      face_root:
        anchors:
          c_accent: "var(--pub4-signal)"
  YAML
end
