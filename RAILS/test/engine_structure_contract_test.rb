# frozen_string_literal: true

require "minitest/autorun"

class EngineStructureContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BRGEN = File.join(ROOT, "brgen")
  TAKEAWAY = "brgen/engines/marketplace/engines/takeaway"

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_takeaway_remains_the_marketplace_food_engine
    assert File.file?(File.join(BRGEN, "engines/marketplace/engines/takeaway/lib/takeaway/engine.rb"))
    assert File.file?(File.join(BRGEN, "engines/marketplace/lib/marketplace.rb"))

    marketplace_entry = File.read(File.join(BRGEN, "engines/marketplace/lib/marketplace.rb"))
    assert_includes marketplace_entry, 'require_relative "../engines/takeaway/lib/takeaway"'

    routes = File.read(File.join(BRGEN, "config/routes.rb"))
    assert_match(/mount Takeaway::Engine, at: "\/food".*MARKETPLACE_SUBDOMAINS/m, routes)
    assert_match(/mount Takeaway::Engine, at: "\/".*TAKEAWAY_SUBDOMAINS/m, routes)
  end

  def test_takeaway_has_no_second_gemfile_or_database
    refute File.exist?(File.join(BRGEN, TAKEAWAY, "Gemfile"))
    refute File.exist?(File.join(BRGEN, TAKEAWAY, "Gemfile.lock"))
    refute File.directory?(File.join(BRGEN, TAKEAWAY, "db"))
  end

  def test_the_only_nested_engine_is_the_declared_takeaway_boundary
    nested = Dir.glob(File.join(BRGEN, "engines/**/engines/*"))
                .select { |path| File.directory?(path) }
                .map { |path| path.delete_prefix("#{ROOT}/") }
                .sort
    assert_equal [TAKEAWAY], nested
  end

  def test_architecture_contract_keeps_the_nested_food_boundary_explicit
    contract = File.read(File.join(ROOT, "..", "MASTER", "data", "law", "TREE_CONTRACTS.md"))
    assert_includes contract, "RAILS/brgen/engines/marketplace/engines/takeaway"
    assert_includes contract, "exposed at `/food`"
  end
end
