# frozen_string_literal: true

require "test_helper"
require "brgen/domain_registry"
require "brgen/city_seed"

class CitySeedTest < ActiveSupport::TestCase
  def rows
    @rows ||= Brgen::CitySeed.rows_from_registry
  end

  def by_domain
    @by_domain ||= rows.index_by(&:domain)
  end

  test "every catalogue city becomes a complete seed row" do
    records = Brgen::DomainRegistry::CITY_RECORDS.index_by { |record| record.fetch("domain") }
    domains = records.keys.sort
    assert_equal 43, domains.length, "city seed inventory must cover all registered cities"

    assert_equal domains, Brgen::DomainRegistry::ENTRIES.map(&:domain).sort
    assert_equal domains, rows.map(&:domain).sort

    rows.each do |row|
      record = records.fetch(row.domain)
      assert_equal record.fetch("city"), row.name
      assert_equal record.fetch("country"), row.country_code
      assert_equal record.fetch("locale"), row.locale
      assert_equal record.fetch("currency"), row.currency
      assert_equal record.fetch("time_zone"), row.time_zone
      assert_equal record.fetch("latitude"), row.latitude
      assert_equal record.fetch("longitude"), row.longitude
      refute_equal 0, row.latitude, "#{row.domain} latitude is 0"
      refute_equal 0, row.longitude, "#{row.domain} longitude is 0"
    end
  end

  test "no two cities share 0,0" do
    origins = rows.select { |row| row.latitude.zero? && row.longitude.zero? }
    assert_empty origins.map(&:domain)
  end

  test "US eastern cities are not America/Los_Angeles" do
    %w[newyrk.us wshingtondc.com dtroit.us].each do |domain|
      refute_equal "America/Los_Angeles", by_domain.fetch(domain).time_zone, domain
    end
    assert_equal "America/New_York", by_domain.fetch("newyrk.us").time_zone
    assert_equal "America/New_York", by_domain.fetch("wshingtondc.com").time_zone
    assert_equal "America/Detroit", by_domain.fetch("dtroit.us").time_zone
  end
end
