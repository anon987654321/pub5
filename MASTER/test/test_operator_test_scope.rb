# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/test_scope"

class TestOperatorTestScope < Minitest::Test
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

    env = Operator::TestScope.app_environment(root: "/repo", app: "brgen", inherited_env: parent)

    assert_equal "/repo/RAILS/brgen/Gemfile", env.fetch("BUNDLE_GEMFILE")
    %w[BUNDLE_PATH BUNDLE_WITHOUT BUNDLER_ORIG_GEM_HOME RUBYOPT].each do |key|
      assert_nil env.fetch(key), "#{key} leaked from MASTER into the Rails test child"
    end
  end

  def test_unrelated_rails_paths_do_not_claim_an_app_suite
    assert_empty Operator::TestScope.rails_apps(%w[test checks])
  end
end
