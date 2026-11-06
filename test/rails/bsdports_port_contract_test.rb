# frozen_string_literal: true

require "minitest/autorun"

class BsdportsPortContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_bsdports_is_an_independent_rails_application_on_the_pinned_runtime
    gemfile = File.read(File.join(ROOT, "rails/bsdports/Gemfile"))
    application = File.read(File.join(ROOT, "rails/bsdports/config/application.rb"))
    assert_includes gemfile, 'ruby "3.4.9"'
    assert_includes gemfile, 'gem "rails", "= 8.1.4.1"'
    assert_includes gemfile, 'gem "pub5-shared", path: "../shared"'
    assert_includes application, "config.load_defaults 8.1"
  end

  def test_database_configuration_contains_no_production_database_bytes
    database = File.read(File.join(ROOT, "rails/bsdports/config/database.yml"))
    assert_includes database, "storage/production.sqlite3"
    refute File.exist?(File.join(ROOT, "rails/bsdports/storage/production.sqlite3"))
  end

  def test_runtime_and_cutover_are_not_claimed
    status = File.read(File.join(ROOT, "rails/bsdports/PORT_STATUS.yml"))
    assert_includes status, "runtime: NOT_RUN"
    assert_includes status, "production_cutover: BLOCKED"
  end
end
