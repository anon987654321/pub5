# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class CityCatalogueContractTest < Minitest::Test
  REPOSITORY_ROOT = File.expand_path("../..", __dir__)
  BRGEN_ROOT = File.join(REPOSITORY_ROOT, "RAILS", "brgen")
  CATALOGUE = File.join(BRGEN_ROOT, "config", "cities.yml")
  REGISTRY = File.join(BRGEN_ROOT, "lib", "brgen", "domain_registry.rb")
  CITY_SEED = File.join(BRGEN_ROOT, "lib", "brgen", "city_seed.rb")

  FIELDS = %w[
    city country currency domain latitude longitude locale marketplace_subdomain time_zone
  ].freeze

  def records
    @records ||= YAML.safe_load_file(CATALOGUE, aliases: false)
  end

  def test_catalogue_has_unique_complete_city_records
    refute_empty records
    domains = records.map { |record| record.fetch("domain") }
    assert_equal domains.length, domains.uniq.length, "city domains must be unique"

    records.each do |record|
      assert_equal FIELDS, record.keys.sort
      %w[city country currency domain locale marketplace_subdomain time_zone].each do |field|
        refute_empty record.fetch(field).to_s.strip, "#{record["domain"]}: #{field} is empty"
      end
      assert_match(/\A[A-Z]{2}\z/, record.fetch("country"))
      assert_match(/\A[A-Z]{3}\z/, record.fetch("currency"))
      assert_match(/\A[a-z]{2}(?:-[A-Z]{2})?\z/, record.fetch("locale"))
      assert_match(/\A[A-Za-z0-9_+-]+(?:\/[A-Za-z0-9_+-]+)+\z/, record.fetch("time_zone"))
      assert_operator record.fetch("latitude"), :>=, -90
      assert_operator record.fetch("latitude"), :<=, 90
      assert_operator record.fetch("longitude"), :>=, -180
      assert_operator record.fetch("longitude"), :<=, 180
    end
  end

  def test_runtime_registry_and_seed_read_the_same_catalogue
    registry = File.read(REGISTRY)
    seed = File.read(CITY_SEED)

    assert_includes registry, 'YAML.safe_load_file(CITY_CATALOGUE_PATH, aliases: false)'
    assert_includes registry, "CITY_RECORDS.map"
    refute_match(/^\s*ENTRIES\s*=\s*\[\s*Entry\.new/m, registry)
    assert_includes seed, "Brgen::DomainRegistry::CITY_RECORDS"
    refute_match(/^\s*COORDINATES\s*=/, seed)
    refute_match(/^\s*TIME_ZONES\s*=/, seed)
    refute_match(/CityRow\.new\("brgen\.no"/, seed)
  end
end
