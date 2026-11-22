# frozen_string_literal: true

require_relative "test_helper"

# The law catalogue contains the governing principles and execution policy;
# executable law lives in MASTER/law/*.rb. These tests assert each authority
# without creating a second rule catalogue in YAML.
class TestLawsRegistry < Minitest::Test
  def laws
    require File.expand_path("../law/definition", __dir__)
    ::Law.load_all(File.expand_path("../law", __dir__)) if ::Law.definitions.empty?
    ::Law.definitions.values
  end

  def test_executable_law_registry_is_not_quietly_empty
    assert_operator laws.size, :>=, 100, "expected a substantial executable law registry"
  end

  def test_every_executable_law_has_an_id
    missing = laws.each_with_index.filter_map do |law, i|
      "laws[#{i}]" if law.id.to_s.strip.empty?
    end

    assert_empty missing, "executable laws without an id: #{missing.join(', ')}"
  end

  def test_executable_law_ids_are_unique
    duplicates = laws.map { |law| law.id.to_s }.tally.select { |_, n| n > 1 }.keys

    assert_empty duplicates, "duplicate executable law ids: #{duplicates.join(', ')}"
  end

  def test_every_executable_law_carries_proof_metadata
    invalid = laws.reject do |law|
      law.respond_to?(:bad) && law.respond_to?(:good) && law.respond_to?(:fix)
    end

    assert_empty invalid.map(&:id), "laws missing proof metadata: #{invalid.map(&:id).join(', ')}"
  end

  def test_public_outbound_address_pinning_is_an_executable_law
    law = laws.find { |candidate| candidate.id.to_s == "ROBUSTNESS_outbound_fetch_is_pinned" }

    refute_nil law, "the canonical outbound SSRF Law must be executable"
    assert_match(/A and AAAA address/, law.ask)
    assert_match(/pin the socket/, law.ask)
    assert_match(/redirect/, law.ask)
    assert_match(/ambient proxy/, law.fix)
    assert_match(/loopback daemon probes/, law.fix)
  end
end
