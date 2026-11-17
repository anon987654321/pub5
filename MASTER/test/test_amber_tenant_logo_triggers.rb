# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

# The amber-tenant-logo skill is context-triggered: when brgen creates a new
# tenant that needs a logo, the skill fires without anyone naming it, and it
# stays silent on work that is not a tenant or a mark. These proofs hold the
# trigger set and the law body it carries.
class AmberTenantLogoTriggersTest < Minitest::Test
  def skill
    data = YAML.safe_load_file(File.expand_path("../data/patterns.yml", __dir__), aliases: true)
    data.fetch("skills_registry").fetch("skills").find { |s| s["name"] == "amber-tenant-logo" } ||
      flunk("amber-tenant-logo missing from the skills registry")
  end

  def triggers
    skill.fetch("triggers").map { |t| Regexp.new(t) }
  end

  # The contexts the skill exists for. Each names the situation in the words
  # an operator actually uses; every one must fire.
  def test_fires_on_tenant_creation_and_logo_contexts
    contexts = [
      "brgen creates a new tenant that needs a logo",
      "run the new tenant onboarding flow for a city",
      "we are adding a new city to brgen",
      "what logo should the new Oslo tenant use?",
      "render the amber plate for the new tenant",
    ]
    contexts.each do |context|
      assert triggers.any? { |re| context.match?(re) }, "no trigger fired for: #{context}"
    end
  end

  def test_stays_silent_outside_the_tenant_and_mark_context
    contexts = [
      "fix the checkout form validation",
      "the marketplace search index is stale",
      "rewrite the courier shift report",
    ]
    contexts.each do |context|
      refute triggers.any? { |re| context.match?(re) }, "a trigger fired for unrelated work: #{context}"
    end
  end

  # The body carries the law: one artwork, nine hairlines, the generator, the
  # reviewed-variant install path, and the contract test that holds it.
  def test_body_states_the_amber_law
    body = skill.fetch("body")
    %w[Caprasimo hairline __logo/generate.mjs logo_contract_test.rb VARIANT_ASSETS AMBER_LOGO_VARIANT].each do |fact|
      assert body.include?(fact), "skill body lost the law fact: #{fact}"
    end
  end
end
