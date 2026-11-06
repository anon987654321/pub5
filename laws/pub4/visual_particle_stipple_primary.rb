# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/recovered_design_semantics.rb:179 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1c2aec43827329f7
require_relative "master/law/recovered_design_semantics"

Law.define(:VISUAL_PARTICLE_STIPPLE_PRIMARY) do
  path "MASTER/data/tokens.yml"
  source "pub4 primary material - greyscale particle stipple, many carriers resolving into one form"
  scope :file

  detect do |text|
    tokens = YAML.safe_load(text, aliases: true).fetch("tokens")
    face = tokens.fetch("face_interface")

    modes = face.fetch("state").fetch("modes").map(&:to_s).sort
    forces = face.fetch("stipple_force")
    memberships = face.fetch("stipple_membership")

    force_words = %w[residual ripple gather fragment settle]
    membership_words = %w[unturned transitional turned locked]
    required_terms = %w[pluribus unum signal turned unturned residual void gather ripple fragment settle]
    required_bans = %w[solid_mesh_as_primary_face_material motion_without_semantic_state
                       signal_as_large_background_fill erasing_all_residual_individuality_in_idle]

    tokens.fetch("visual_identity").fetch("material") != "greyscale_particle_stipple" ||
      !required_terms.all? { |term| face.fetch("stipple_vocabulary").fetch(term).to_s.strip != "" } ||
      forces.keys.sort != modes || memberships.keys.sort != modes ||
      !(forces.values - force_words).empty? || !(memberships.values - membership_words).empty? ||
      forces.fetch("idle") != "residual" ||
      !(required_bans - face.fetch("stipple_forbidden")).empty?
  rescue Psych::Exception, KeyError, TypeError, ArgumentError
    true
  end

  fix "Keep greyscale particle stipple as the identity material; give every face state a membership and " \
      "a force from the stipple vocabulary, and let idle keep its residual."

  bad <<~YAML
    tokens:
      visual_identity:
        material: "glossy_mesh_skin"

      face_interface:
        state:
          modes: [idle]

        stipple_vocabulary: {}
        stipple_membership: { idle: turned }
        stipple_force: { idle: glow }
        stipple_forbidden: []
  YAML

  good <<~YAML
    tokens:
      visual_identity:
        material: "greyscale_particle_stipple"

      face_interface:
        state:
          modes: [idle]

        stipple_vocabulary:
          pluribus: "many discrete carriers"
          unum: "one readable form"
          signal: "propagating change"
          turned: "admitted into the field"
          unturned: "not yet joined"
          residual: "the particular inside the collective"
          void: "negative space"
          gather: "parts pull toward one locus"
          ripple: "a signal crosses the field"
          fragment: "parts leave the form"
          settle: "the field re-coheres"

        stipple_membership: { idle: transitional }
        stipple_force: { idle: residual }
        stipple_forbidden:
          - solid_mesh_as_primary_face_material
          - motion_without_semantic_state
          - signal_as_large_background_fill
          - erasing_all_residual_individuality_in_idle
  YAML
end
