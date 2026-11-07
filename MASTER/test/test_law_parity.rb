# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/fix/law_parity"

class TestLawParity < Minitest::Test
  def test_all_nine_invariant_laws_declare_both_modalities
    parity = Master::Fix::LawParity.new
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    nodes = Master::FlatLawCatalogue.entries(catalogue).select { |entry| entry["node"] }

    assert_equal 9, nodes.size
    assert nodes.all? { |entry| entry["mechanical"].to_s.strip != "" }
    assert nodes.all? { |entry| entry["semantic"].to_s.strip != "" }
    assert nodes.all? { |entry| entry["enforcement"] == "declared" }
    assert_empty parity.call, parity.report
    assert_match(/declarations complete/, parity.report)
  end

  def test_parity_does_not_claim_that_declared_detectors_have_executed
    report = Master::Fix::LawParity.new.report

    assert_match(/execution evidence measured separately/, report)
    refute_match(/runtime enforcement passed|all detectors passed/i, report)
  end

  def test_missing_modality_declaration_invalidates_the_constitution
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    catalogue.fetch("ROBUSTNESS").delete("mechanical")

    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!(catalogue)
    end
    assert_match(/ROBUSTNESS must declare mechanical enforcement/, error.message)
  end

  def test_deterministic_coverage_must_name_a_detector
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    catalogue.fetch("TRUTHFUL_STATUS")["detector_ids"] = []

    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!(catalogue)
    end
    assert_match(/deterministic coverage must name detector_ids/, error.message)
  end

  def test_numeric_priority_is_rejected_from_the_normative_catalogue
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    catalogue.fetch("ROBUSTNESS")["priority"] = 1

    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!(catalogue)
    end
    assert_match(/retired ranking field/, error.message)
  end

  def test_empty_catalogue_is_not_reported_as_clean
    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!({})
    end
    assert_match(/no flat laws/, error.message)
  end

  def test_enforcement_overlay_has_been_retired
    refute File.exist?(File.join(Master::ROOT, "data", "law_enforcement.yml"))
  end

  def test_a_renamed_famous_law_is_rejected
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    catalogue["CLARITY_OVER_CLEVERNESS"] = catalogue.delete("KISS")

    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!(catalogue)
    end
    assert_match(/famous law KISS must keep its name/, error.message)
  end

  def test_famous_name_families_survive_with_their_children
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    ids = catalogue.keys.map(&:to_s)

    Master::FlatLawCatalogue::FAMOUS_NAMES.each do |name|
      assert ids.any? { |id| id == name || id.start_with?("#{name}_") },
             "#{name} is named as famous but no law keeps that id"
    end
  end

  def test_a_measured_only_law_cannot_also_resolve_automatic
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    row = catalogue.fetch("CQS")
    row["resolution"] = "automatic"
    row["proof"] = "test/test_law_parity.rb"

    error = assert_raises(Master::FlatLawCatalogue::Invalid) do
      Master::FlatLawCatalogue.validate!(catalogue)
    end
    assert_match(/measurement_only and cannot also resolve automatic/, error.message)
  end

  def test_a_declared_enforcement_surface_names_no_phantom_command
    catalogue = Master.load_yaml(Master::Fix::LawParity::LAWS_PATH)
    phantom = Master::FlatLawCatalogue.entries(catalogue).select do |entry|
      entry["enforcement"].to_s.include?("lint:laws#")
    end

    assert_empty phantom.map { |entry| entry.fetch("id") },
                 "these laws name bin/master lint:laws, a command that does not exist"
  end
end
