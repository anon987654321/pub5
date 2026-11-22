# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/test_scope"

class TestOperatorTestScope < Minitest::Test
  def test_explicit_rails_root_routes_to_every_active_app_suite
    assert_equal %w[brgen amber bsdports mrdamascy], Operator::TestScope.rails_apps(%w[RAILS])
  end

  def test_suite_scope_tracks_registered_rails_apps_and_shared_engine_gemfiles
    inventory = Master::Fix::RailsApp.app_paths(repo_root: Master::ROOT)
    registered_rails_apps = inventory.select { |_name, directory| directory.start_with?("RAILS/") }.keys
    shared_consumers = Master::Fix::RailsApp.engine_apps(repo_root: Master::ROOT)

    assert_equal registered_rails_apps.sort, Operator::TestScope.rails_apps(%w[RAILS]).sort
    assert_equal shared_consumers.sort, Operator::TestScope.rails_apps(%w[__shared]).sort
  end

  def test_shared_engine_routes_to_every_dependent_app_suite
    assert_equal %w[brgen amber bsdports], Operator::TestScope.rails_apps(%w[__shared])
  end

  def test_shared_engine_and_app_paths_deduplicate_the_suite_list
    assert_equal %w[brgen amber bsdports],
                 Operator::TestScope.rails_apps(%w[__shared brgen amber])
  end

  def test_standalone_mrdamascy_routes_to_its_own_suite
    assert_equal %w[mrdamascy], Operator::TestScope.rails_apps(%w[mrdamascy])
  end

  def test_an_individual_shared_consumer_stays_targeted
    assert_equal %w[amber], Operator::TestScope.rails_apps(%w[amber])
  end

  def test_app_environment_selects_the_app_gemfile_and_clears_master_bundle_state
    parent = {
      "BUNDLE_GEMFILE" => "/repo/MASTER/Gemfile",
      "BUNDLE_PATH" => "/repo/MASTER/.bundle",
      "BUNDLE_WITHOUT" => "test",
      "BUNDLER_ORIG_GEM_HOME" => "/old/gems",
      "RUBYOPT" => "-rbundler/setup",
    }

    root = Master::ROOT
    env = Operator::TestScope.app_environment(root:, app: "brgen", inherited_env: parent)
    expected = File.join(Master::Fix::RailsApp.app_dir("brgen", repo_root: root), "Gemfile")

    assert_equal expected, env.fetch("BUNDLE_GEMFILE")
    %w[BUNDLE_PATH BUNDLE_WITHOUT BUNDLER_ORIG_GEM_HOME RUBYOPT].each do |key|
      assert_nil env.fetch(key), "#{key} leaked from MASTER into the Rails test child"
    end
    assert_raises(ArgumentError) do
      Operator::TestScope.app_environment(root:, app: "master", inherited_env: parent)
    end
  end

  def test_operator_test_command_uses_the_canonical_scope_and_app_environment
    source = File.read(File.join(Master::ROOT, "bin", "operator"))

    assert_includes source, "Operator::TestScope.rails_apps(rails_parts)"
    assert_includes source, "Operator::TestScope.app_environment(root: ROOT, app:)"
    refute_includes source, 'rails_parts.include?("shared")'
  end

  def test_unrelated_rails_paths_do_not_claim_an_app_suite
    assert_empty Operator::TestScope.rails_apps(%w[test checks])
  end
end
