# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class RailsRegistryContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def setup
    @registry = YAML.safe_load_file(File.join(ROOT, "registry/apps.yml"), aliases: true)
  end

  def test_rails_registry_uses_stable_rails_and_the_host_ruby
    assert_equal "8.1.4.1", @registry.dig("rails_stack", "rails").to_s
    assert_equal "rubygems", @registry.dig("rails_stack", "rails_source")
    assert_equal "8.1.4.1", @registry.dig("rails_stack", "rails_ref").to_s
  end

  def test_master_web_is_not_recorded_as_a_rails_app
    assert_includes @registry.dig("apps", "master", "stack_now"), "Roda + Sequel"
  end

  def test_rails_app_roots_follow_the_lowercase_tree_contract
    %w[brgen amber bsdports mrdamascy].each do |name|
      root = @registry.dig("apps", name, "deploy_root")
      assert_match(%r{\Arails/apps/#{name}\z}, root)
    end
  end
end
