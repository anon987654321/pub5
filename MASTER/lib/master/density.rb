# frozen_string_literal: true

module Master
  # Mechanical detectors for the DENSITY_kanso children.
  #
  # Kanso is simplicity by subtraction: what remains must earn its place.
  # The parent Law (DENSITY_kanso) stays the normative statement and keeps
  # resolution: review — these methods measure proxies, they do not judge
  # aesthetics. Each instrumented child names its method here through its
  # laws.yml `mechanical:` entry; the two children with no method
  # (DENSITY_kanso_conceptual_duplication, DENSITY_kanso_material_dishonesty)
  # deliberately have none: consolidation and material honesty are judgment,
  # and a detector that always returns [] would be a stub wearing a Law id.
  #
  # Lives flat under lib/master/ with Random and Time on purpose: the
  # directory sits outside Zeitwerk (data/autoload.yml), a new law/ namespace
  # for one file is exactly the lone directory the sprawl census prices, and
  # the flat name is what the runtime actually answers to.
  #
  # Input is one KansoSurfaceCheck payload — the hash the rendered kanso
  # probe returns per surface×viewport (string keys, the same convention as
  # the geometry walk payload):
  #
  #   "vw" / "vh"               viewport size
  #   "wrapper_chains"          consecutive single-child pass-through
  #                             containers (own text absent, not interactive,
  #                             not landmark, no role/aria), each with
  #                             path, depth, styled (any level paints),
  #                             dead (subtree carries no text/interactive/
  #                             media at all) and area of the outermost box
  #   "dead_regions"            visible painted containers whose whole
  #                             subtree carries no content
  #   "shadow_chrome"           first-screen boxes with a box-shadow but no
  #                             text, no interactivity, no media, no role
  #   "ornament_pseudo"         boxes whose ::before/::after paints while the
  #                             box itself carries no content
  #   "z_values"                distinct non-auto z-index values on screen
  #   "gaps"                    vertical gaps between consecutive major
  #                             siblings: above, below, gap (px)
  #   "painted_area_ratio"      sum of first-screen box areas / viewport area
  #   "focal_area_ratio"        largest content box / viewport area
  #   "content_free_area_ratio" area painted by content-free boxes / painted
  #                             area
  #
  # Findings are plain hashes: { law:, message:, evidence:, autofix: }.
  # `autofix:` is a hint the pipeline may honour — :collapse for unstyled
  # wrapper chains (pure structure, removal cannot change paint) and :none
  # everywhere else, because every other kanso offender is painted and
  # removing painted ink changes the page. No pen exists for any kanso
  # finding yet; the hint states what WOULD be mechanical, not what already
  # runs.
  module Density
    # Gaps at or above this may read as intentional ma rather than residue.
    MA_GAP_FLOOR = 64
    # The spacing scale the design tokens declare; the rendered geometry
    # check reads the same list from tokens.yml with this fallback.
    ALLOWED_SPACING = [4, 8, 16, 24, 32, 48, 64].freeze
    # A pass-through chain shorter than this is normal component structure
    # (a card in a grid cell in a section), not clutter.
    MIN_CHAIN_DEPTH = 3
    # Distinct z-index values beyond this read as an arbitrary stack. Real
    # pages legitimately keep a few (dropdown, modal, toast); the count is
    # evidence for the aggregate finding, never per-element.
    MAX_DISTINCT_Z = 5
    # First-screen painted area per viewport area. Overlap can exceed 1.0;
    # the ceiling is the initial calibration proxy and stays soft until
    # calibrated against the declared surfaces.
    CLUTTER_CEILING = 0.45
    # Largest single content box per viewport area. A primary surface whose
    # dominant region is smaller than this is competing with itself.
    CLARITY_FLOOR = 0.15
    # Share of painted area owned by content-free boxes before the parent
    # aggregate finding fires.
    CONTENT_FREE_CEILING = 0.2

    module_function

    # Parent entry point — every instrumented child, in laws.yml order.
    def kanso(payload, surface: nil)
      [
        *kanso_visual_noise(payload, surface:),
        *kanso_structural_clutter(payload, surface:),
        *kanso_space_not_earned(payload, surface:),
      ]
    end

    # DENSITY_kanso_visual_noise — decorative chrome that carries nothing.
    # Shadow-only boxes, ornamental pseudo-element paint, and an arbitrary
    # z-stack are the three measurable shapes; competing visual weights on
    # real content stay on the review path because weight is judgment.
    def kanso_visual_noise(payload, surface: nil)
      findings = []

      Array(payload["shadow_chrome"]).first(8).each do |box|
        findings << {
          law: "DENSITY_kanso_visual_noise",
          message: "#{where(surface)} decorative box #{box["key"]} paints a shadow and carries " \
                   "no text, control, media, or role - ornament that only adds ink",
          evidence: { key: box["key"], rect: box["rect"], shadow: box["shadow"].to_s[0, 60] },
          autofix: :none,
        }
      end

      Array(payload["ornament_pseudo"]).first(8).each do |box|
        findings << {
          law: "DENSITY_kanso_visual_noise",
          message: "#{where(surface)} #{box["key"]} paints #{box["pseudo"]} while carrying no " \
                   "content of its own - ornamental pseudo-element",
          evidence: { key: box["key"], pseudo: box["pseudo"] },
          autofix: :none,
        }
      end

      z_values = Array(payload["z_values"]).map { |z| z.to_s.to_i }.select(&:positive?).uniq.sort
      return findings unless z_values.size > MAX_DISTINCT_Z

      findings << {
        law: "DENSITY_kanso_visual_noise",
        message: "#{where(surface)} stacks #{z_values.size} distinct z-index values " \
                 "(#{z_values.first(8).join(', ')}) - an arbitrary stack is visual noise " \
                 "and usually hides an untold layering story",
        evidence: { z_values: z_values },
        autofix: :none,
      }
      findings
    end

    # DENSITY_kanso_structural_clutter — nesting that adds no hierarchy.
    # Pass-through chains of MIN_CHAIN_DEPTH or more, and painted regions
    # whose entire subtree carries no content.
    def kanso_structural_clutter(payload, surface: nil)
      findings = []

      Array(payload["wrapper_chains"]).select { |chain| chain["depth"].to_i >= MIN_CHAIN_DEPTH }
                                     .first(6)
                                     .each do |chain|
        findings << {
          law: "DENSITY_kanso_structural_clutter",
          message: "#{where(surface)} nests #{chain["depth"]} pass-through containers " \
                   "(#{chain["path"]}) - wrappers that add depth but no hierarchy" \
                   "#{'; the outermost paints an empty region' if chain['dead']}",
          evidence: { path: chain["path"], depth: chain["depth"], styled: chain["styled"], dead: chain["dead"] },
          autofix: chain["styled"] ? :none : :collapse,
        }
      end

      Array(payload["dead_regions"]).first(6).each do |region|
        # A dead region is painted by definition - that is the only reason
        # it is measurable here. Removing one changes paint, so no autofix
        # hint claims it; deletion of unstyled invisible boxes is not a
        # rendered measurement at all.
        findings << {
          law: "DENSITY_kanso_structural_clutter",
          message: "#{where(surface)} paints region #{region["key"]} (#{region["rect"]["w"].to_i}x" \
                   "#{region["rect"]["h"].to_i}) whose whole subtree carries no text, control, or media",
          evidence: { key: region["key"], rect: region["rect"] },
          autofix: :none,
        }
      end

      findings
    end

    # DENSITY_kanso_space_not_earned — residual gaps, not intentional ma.
    # Ownership boundary with the rendered geometry rhythm check: an
    # off-scale gap alone is rhythm (rendered_geometry owns that finding).
    # Kanso claims a gap only when the leftover reads as residue of
    # unremoved clutter — a near-miss off the scale, or any off-scale gap
    # on a surface that also paints dead regions or long wrapper chains.
    def kanso_space_not_earned(payload, surface: nil)
      cluttered = Array(payload["dead_regions"]).any? ||
                  Array(payload["wrapper_chains"]).any? { |c| c["depth"].to_i >= MIN_CHAIN_DEPTH }

      residual = Array(payload["gaps"]).select do |gap|
        px = gap["gap"].to_f
        next false if px <= 0 || px >= MA_GAP_FLOOR
        next false if ALLOWED_SPACING.include?(px.round)
        next false if (px.round % 8).zero?

        near_miss?(px) || cluttered
      end
      return [] if residual.empty?

      residual.first(5).map do |gap|
        {
          law: "DENSITY_kanso_space_not_earned",
          message: "#{where(surface)} leaves a #{gap["gap"].to_i}px gap between " \
                   "#{gap["above"]} and #{gap["below"]} - off the spacing scale and not " \
                   "wide enough to read as intentional ma",
          evidence: { above: gap["above"], below: gap["below"], gap_px: gap["gap"] },
          autofix: :none,
        }
      end
    end

    # Parent-law aggregates: the numeric envelope a surface must sit inside
    # before its kanso proxies count as measured-and-clear. These fire under
    # DENSITY_kanso itself so the ratchet can later tighten them without
    # touching a child Law.
    def kanso_envelope(payload, surface: nil)
      findings = []

      ratio = payload["painted_area_ratio"].to_f
      if ratio.positive? && ratio > CLUTTER_CEILING
        findings << {
          law: "DENSITY_kanso",
          message: "#{where(surface)} paints #{(ratio * 100).round(1)}% of the viewport - " \
                   "above the #{(CLUTTER_CEILING * 100).round(1)}% clutter envelope (proxy, uncalibrated)",
          evidence: { painted_area_ratio: ratio, ceiling: CLUTTER_CEILING },
          autofix: :none,
        }
      end

      focal = payload["focal_area_ratio"].to_f
      if focal.positive? && focal < CLARITY_FLOOR
        findings << {
          law: "DENSITY_kanso",
          message: "#{where(surface)} has no dominant region - the largest content box covers " \
                   "#{(focal * 100).round(1)}% of the viewport, under the #{(CLARITY_FLOOR * 100).round(1)}% " \
                   "clarity floor (proxy, uncalibrated)",
          evidence: { focal_area_ratio: focal, floor: CLARITY_FLOOR },
          autofix: :none,
        }
      end

      free = payload["content_free_area_ratio"].to_f
      if free.positive? && free > CONTENT_FREE_CEILING
        findings << {
          law: "DENSITY_kanso",
          message: "#{where(surface)} spends #{(free * 100).round(1)}% of its painted area on " \
                   "boxes that carry no content - ink that does not say anything",
          evidence: { content_free_area_ratio: free, ceiling: CONTENT_FREE_CEILING },
          autofix: :none,
        }
      end

      findings
    end

    # A gap within NEAR_MISS_PX of a scale value is a near miss - the shape
    # that reads as a mistake rather than a choice (the same near-miss
    # principle as the rendered edge-alignment check).
    NEAR_MISS_PX = 3.0

    def near_miss?(px)
      ALLOWED_SPACING.any? { |allowed| (px - allowed).abs <= NEAR_MISS_PX && (px - allowed).abs.positive? }
    end

    def where(surface)
      surface ? "kanso #{surface}:" : "kanso:"
    end
  end
end
