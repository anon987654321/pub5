# frozen_string_literal: true

require_relative "test_helper"
# Files under lib/master/ are outside Zeitwerk (data/autoload.yml), so the
# module is required by path, exactly like its sibling master/time.rb.
require_relative "../lib/master/density"

# Proof fixtures for the DENSITY_kanso children.
#
# The rendered kanso probe needs Chrome and a booted app, so its catalogue
# entries are honest about what runs where: the two automatic children carry
# `proof:` pointing at the tests in this file, which drive
# Master::Density directly against fixture payloads — the same payload
# shape geometry_probe/kanso.js returns. A detector that flags clutter on a
# clean surface, or stays silent on a cluttered one, is wrong in exactly the
# way a browser run could not catch until calibration day.
#
# The parent Law keeps resolution: review on purpose: these tests prove the
# proxies detect, they do not prove the proxies judge. A surface passing the
# numeric envelope has not "achieved kanso", and no test here says otherwise.
class TestKansoLaws < Minitest::Test
  # A payload the probe would return for a surface with nothing to subtract:
  # every list empty, the envelope comfortably inside.
  CLEAN = {
    "vw" => 390, "vh" => 844,
    "wrapper_chains" => [],
    "dead_regions" => [],
    "shadow_chrome" => [],
    "ornament_pseudo" => [],
    "z_values" => [],
    "gaps" => [],
    "painted_area_ratio" => 0.3,
    "focal_area_ratio" => 0.4,
    "content_free_area_ratio" => 0.05,
  }.freeze

  def test_visual_noise_flags_shadow_only_chrome
    payload = cluttered(
      "shadow_chrome" => [shadow_box("div.hero-glow", 300, 120, "0 0 24px rgba(0,0,0,.4)")],
    )

    findings = Master::Density.kanso_visual_noise(payload, surface: SURFACE)
    refute_empty findings, "a shadow on a content-free box is non-data ink"

    finding = findings.fetch(0)
    assert_equal "DENSITY_kanso_visual_noise", finding[:law]
    assert_includes finding[:message], "div.hero-glow"
    assert_equal :none, finding[:autofix], "removing painted ink changes the page; no pen claims it"
  end

  def test_visual_noise_spares_content_bearing_shadows
    # The probe never reports a shadow on a content-bearing card (affordance,
    # not ink) — the detector holds the same line if handed one anyway.
    assert_empty Master::Density.kanso_visual_noise(CLEAN, surface: SURFACE)
  end

  def test_visual_noise_flags_ornamental_pseudo_element
    payload = cluttered(
      "ornament_pseudo" => [{ "key" => "div.banner", "pseudo" => "::before" }],
    )

    finding = Master::Density.kanso_visual_noise(payload, surface: SURFACE).fetch(0)
    assert_equal "DENSITY_kanso_visual_noise", finding[:law]
    assert_equal "::before", finding[:evidence][:pseudo]
  end

  def test_visual_noise_z_stack_threshold
    few = cluttered("z_values" => [1, 10, 100, 2, 5])
    assert_empty Master::Density.kanso_visual_noise(few, surface: SURFACE),
                 "five values is a dropdown, a modal, a toast and friends - not yet a stack"

    many = cluttered("z_values" => [1, 2, 5, 10, 11, 90, 99, 100])
    finding = Master::Density.kanso_visual_noise(many, surface: SURFACE).fetch(0)
    assert_equal "DENSITY_kanso_visual_noise", finding[:law]
    assert_equal 8, finding[:evidence][:z_values].size
  end

  def test_structural_clutter_flags_wrapper_chain
    payload = cluttered(
      "wrapper_chains" => [chain("div.app > div.x > div.y > div.z", depth: 3, styled: false, dead: false)],
    )

    finding = Master::Density.kanso_structural_clutter(payload, surface: SURFACE).fetch(0)
    assert_equal "DENSITY_kanso_structural_clutter", finding[:law]
    assert_includes finding[:message], "3 pass-through containers"
    assert_equal :collapse, finding[:autofix],
                 "an unstyled chain is pure structure; collapsing it cannot change paint"
  end

  def test_structural_clutter_spares_normal_component_structure
    two_deep = cluttered(
      "wrapper_chains" => [chain("div.grid > div.cell", depth: 2, styled: false, dead: false)],
    )
    assert_empty Master::Density.kanso_structural_clutter(two_deep, surface: SURFACE),
                 "a card in a grid cell in a section is structure, not clutter"

    styled = cluttered(
      "wrapper_chains" => [chain("div.a > div.b > div.c", depth: 3, styled: true, dead: false)],
    )
    finding = Master::Density.kanso_structural_clutter(styled, surface: SURFACE).fetch(0)
    assert_equal :none, finding[:autofix],
                 "a styled chain paints; collapsing it is a rendered change, not a mechanical one"
  end

  def test_structural_clutter_flags_dead_region
    payload = cluttered(
      "dead_regions" => [region("div.leftover", 390, 200)],
    )

    finding = Master::Density.kanso_structural_clutter(payload, surface: SURFACE).fetch(0)
    assert_equal "DENSITY_kanso_structural_clutter", finding[:law]
    assert_includes finding[:message], "390x200"
    assert_equal :none, finding[:autofix], "a painted region changes paint when deleted"
  end

  def test_space_not_earned_splits_rhythm_from_residue
    # The Law statement has two clauses. A near miss off the scale breaks
    # rhythm on its own - that shape reads as a mistake, not a choice (the
    # same principle as the rendered edge-alignment check).
    near_miss = cluttered("gaps" => [gap("section.hero", "section.feed", 10)])
    finding = Master::Density.kanso_space_not_earned(near_miss, surface: SURFACE).fetch(0)
    assert_equal "DENSITY_kanso_space_not_earned", finding[:law]
    assert_equal 10, finding[:evidence][:gap_px]

    # A far-miss off-scale gap on a clean surface belongs to the rhythm
    # check (ownership boundary with rendered_geometry); kanso claims it only
    # when the leftover reads as residue of unremoved clutter.
    far_miss = cluttered("gaps" => [gap("section.hero", "section.feed", 12)])
    assert_empty Master::Density.kanso_space_not_earned(far_miss, surface: SURFACE)

    residue = cluttered(
      "dead_regions" => [region("div.leftover", 390, 200)],
      "gaps" => [gap("section.hero", "section.feed", 12)],
    )
    finding = Master::Density.kanso_space_not_earned(residue, surface: SURFACE).fetch(0)
    assert_equal "DENSITY_kanso_space_not_earned", finding[:law]
    assert_equal 12, finding[:evidence][:gap_px]
  end

  def test_space_not_earned_spares_on_scale_and_intentional_ma
    on_scale = cluttered(
      "dead_regions" => [region("div.leftover", 390, 200)],
      "gaps" => [gap("section.hero", "section.feed", 16), gap("section.feed", "footer", 96)],
    )
    assert_empty Master::Density.kanso_space_not_earned(on_scale, surface: SURFACE),
                 "a scale gap is rhythm; a 96px break is wide enough to read as intentional ma"
  end

  def test_kanso_aggregates_every_instrumented_child
    payload = cluttered(
      "shadow_chrome" => [shadow_box("div.glow", 100, 40, "0 0 8px")],
      "wrapper_chains" => [chain("div.a > div.b > div.c", depth: 3, styled: false, dead: false)],
      "dead_regions" => [region("div.leftover", 390, 200)],
      "gaps" => [gap("section.hero", "section.feed", 10)],
    )

    laws = Master::Density.kanso(payload, surface: SURFACE).map { |f| f[:law] }
    assert_includes laws, "DENSITY_kanso_visual_noise"
    assert_includes laws, "DENSITY_kanso_structural_clutter"
    assert_includes laws, "DENSITY_kanso_space_not_earned"
  end

  def test_kanso_stays_silent_on_a_clean_surface
    assert_empty Master::Density.kanso(CLEAN, surface: SURFACE)
    assert_empty Master::Density.kanso_envelope(CLEAN, surface: SURFACE)
  end

  def test_envelope_flags_a_surface_outside_the_kanso_proxies
    overpainted = cluttered("painted_area_ratio" => 0.6)
    finding = Master::Density.kanso_envelope(overpainted, surface: SURFACE).fetch(0)
    assert_equal "DENSITY_kanso", finding[:law]
    assert_includes finding[:message], "uncalibrated", "the proxy says so itself"

    unfocused = cluttered("focal_area_ratio" => 0.05)
    laws = Master::Density.kanso_envelope(unfocused, surface: SURFACE).map { |f| f[:law] }
    assert_includes laws, "DENSITY_kanso"

    noisy_ink = cluttered("content_free_area_ratio" => 0.5)
    laws = Master::Density.kanso_envelope(noisy_ink, surface: SURFACE).map { |f| f[:law] }
    assert_includes laws, "DENSITY_kanso"
  end

  # -- catalogue shape -----------------------------------------------------

  def test_automatic_children_carry_proof_and_their_proofs_exist
    rows = Master::FlatLawCatalogue.load
    entries = Master::FlatLawCatalogue.entries(rows).to_h { |row| [row.fetch("id"), row] }

    %w[
      DENSITY_kanso_visual_noise
      DENSITY_kanso_structural_clutter
    ].each do |id|
      entry = entries.fetch(id)
      assert_equal "automatic", entry["resolution"], "#{id} resolves mechanically"
      proof = entry.fetch("proof")
      source, method = proof.split("#")
      assert_equal "MASTER/test/test_kanso_laws.rb", source, "#{id} proof points at this file"
      assert_respond_to self, method.to_sym, "#{id} proof names a test that exists"
    end
  end

  def test_the_parent_law_stays_on_the_review_path
    rows = Master::FlatLawCatalogue.load
    parent = Master::FlatLawCatalogue.entries(rows).find { |row| row.fetch("id") == "DENSITY_kanso" }

    assert_equal "review", parent.fetch("resolution"),
                 "the normative statement keeps human judgment; the children are instruments"
    assert_equal "error", parent.fetch("severity"), "the 2026-11 promotion to error"
    assert_equal "DENSITY", parent.fetch("parent")
  end

  def test_every_kanso_child_names_kanso_as_parent
    rows = Master::FlatLawCatalogue.load
    children = Master::FlatLawCatalogue.entries(rows).select do |row|
      row.fetch("id").start_with?("DENSITY_kanso_")
    end

    assert_operator children.size, :>=, 5, "five instruments around the parent"
    children.each do |row|
      assert_equal "DENSITY_kanso", row.fetch("parent"), row.fetch("id")
    end
  end

  # -- fixture helpers -----------------------------------------------------

  SURFACE = "brgen/core/390".freeze

  def cluttered(**overrides)
    # No ActiveSupport in this runtime: stringify by hand, then merge.
    CLEAN.merge(overrides.each_with_object({}) { |(key, value), row| row[key.to_s] = value })
  end

  def shadow_box(key, w, h, shadow)
    { "key" => key, "rect" => { "x" => 0, "y" => 0, "w" => w, "h" => h }, "shadow" => shadow }
  end

  def region(key, w, h)
    { "key" => key, "rect" => { "x" => 0, "y" => 100, "w" => w, "h" => h } }
  end

  def chain(path, depth:, styled:, dead:)
    { "path" => path, "depth" => depth, "styled" => styled, "dead" => dead,
      "area" => "390x120" }
  end

  def gap(above, below, px)
    { "above" => above, "below" => below, "gap" => px }
  end
end
