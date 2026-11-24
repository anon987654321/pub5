# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

class FleetHealthContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO = File.expand_path("../..", __dir__)
  ACTIVE_APPS = %w[amber brgen bsdports].freeze

  def test_active_apps_expose_health_route
    ACTIVE_APPS.each do |app|
      routes = File.read(File.join(ROOT, app, "config", "routes.rb"))
      assert_match(/fleet\.rb/, routes, "#{app} must load shared fleet routes")
    end
    fleet_routes = File.read(File.join(ROOT, "__shared", "config", "routes", "fleet.rb"))
    assert_match(/get ["']health["']/, fleet_routes)
  end

  def test_shared_security_initializers_present
    %w[security_headers.rb content_security_policy.rb].each do |name|
      path = File.join(ROOT, "__shared", "config", "initializers", name)
      assert File.file?(path), "missing #{name}"
      refute_includes File.read(path), "# Rails.application.configure do\n#", "#{name} should be active"
    end
  end

  # deploy_inventory.json is what vm23 serves; a deployed: false app (mrdamascy)
  # lives in apps.yml without a host, so the mirror covers the deployed set.
  def deployed_apps
    require "yaml"
    apps = YAML.safe_load(File.read(File.join(ROOT, "apps.yml"))).fetch("apps")
    apps.reject { |_name, meta| meta["deployed"] == false }
  end

  def test_master_json_mirrors_apps_yml
    require "json"
    master = JSON.parse(File.read(File.expand_path("../../OPENBSD/deploy_inventory.json", __dir__)))
    expected = deployed_apps.map { |name, meta| [name, meta["domain"], meta["port"]] }.sort
    actual = master.fetch("apps").map { |row| [row["name"], row["domain"], row["port"]] }.sort
    assert_equal expected, actual
  end

  def test_shared_security_policy_loads_through_the_installed_path_gem
    initializer = File.read(File.join(ROOT, "__shared", "config", "initializers", "security_headers.rb"))
    gemspec = File.read(File.join(ROOT, "__shared", "pub5-shared.gemspec"))
    gemfile = File.read(File.join(ROOT, "brgen", "Gemfile"))
    sync = File.read(File.join(REPO, "RAILS", "_sync.sh"))
    helper = File.read(File.join(REPO, "OPENBSD", "mirror", "usr", "local", "libexec", "rails-sync.ksh"))
    shared_lib = File.join(ROOT, "__shared", "lib")
    feature = File.join(shared_lib, "shared", "cross_origin_resource_policy.rb")

    assert_includes initializer, 'require "shared/cross_origin_resource_policy"'
    refute_includes initializer, 'require_relative "../../lib/shared/cross_origin_resource_policy"'
    assert_includes gemspec, 'spec.require_paths = ["lib"]'
    assert_includes gemfile, 'gem "pub5-shared", path: "../__shared"'
    assert_includes sync, 'rails_sync_app_tree "$app_name" shared'
    assert_includes helper, '"$app_home/__shared"'
    assert File.file?(feature), "shared feature must ship under the gem's lib path"

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I", shared_lib, "-e",
      'require "shared/cross_origin_resource_policy"; abort unless defined?(Shared::CrossOriginResourcePolicy)'
    )
    assert status.success?, "shared gem feature failed to load: #{stdout}#{stderr}"
  end

  def test_production_baseline_excludes_health_from_host_auth
    baseline = File.read(File.join(ROOT, "__shared", "config", "environments", "production_baseline.rb"))
    assert_match(%r{/health}, baseline)
    assert_match(/force_ssl = false/, baseline)
  end
end
