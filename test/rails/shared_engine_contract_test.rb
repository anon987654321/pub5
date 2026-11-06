# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class SharedEngineContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_shared_engine_is_a_rails_engine_and_uses_pub5_gem_identity
    gemspec = File.read(File.join(ROOT, "rails/shared/pub5-shared.gemspec"))
    engine = File.read(File.join(ROOT, "rails/shared/lib/shared/engine.rb"))
    assert_includes gemspec, 'spec.name = "pub5-shared"'
    assert_includes engine, "class Engine < ::Rails::Engine"
    assert_includes engine, "isolate_namespace Shared"
  end

  def test_brgen_and_amber_have_one_shared_post_presentation
    paths = %w[rails/shared/app/views/shared/_post_card.html.erb rails/shared/app/views/shared/_post_vote_rail.html.erb rails/shared/app/assets/stylesheets/_post_voting.scss]
    paths.each { |path| assert File.file?(File.join(ROOT, path)), "missing shared presentation source: #{path}" }
    manifest = YAML.safe_load_file(File.join(ROOT, "rails/port.yml"), aliases: false)
    assert_equal "source_preserved_app_wiring_pending", manifest.dig("shared_engine", "status")
  end

  def test_app_inventory_keeps_the_expected_process_boundaries
    manifest = YAML.safe_load_file(File.join(ROOT, "rails/port.yml"), aliases: false)
    assert_equal %w[bsdports brgen amber mrdamascy], manifest.fetch("apps").keys
    assert_equal %w[dating maps marketplace messenger radio tv], manifest.dig("apps", "brgen", "engines")
    assert_equal "BLOCKED", manifest.dig("cutover", "status")
  end
end
