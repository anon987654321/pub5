# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "yaml"
require "json"
require "fileutils"
require_relative "../lib/cli/operator_intent"

class OperatorIntentTest < Minitest::Test
  FakeAgent = Struct.new(:reply, :calls) do
    def ask_once(prompt, **options)
      calls << { prompt:, options: }
      reply
    end
  end

  def with_inventory
    Dir.mktmpdir("operator-intent") do |root|
      FileUtils.mkdir_p(File.join(root, "RAILS"))
      apps = {
        "control_web" => {
          "title" => "Control Web", "domain" => "control.example.test", "port" => 5100,
          "deploy_script" => "OPENBSD/control.sh", "deploy_root" => "MASTER/web",
          "public" => true, "deploy_order" => 10,
        },
        "city_app" => {
          "title" => "City App", "domain" => "city.example.test", "port" => 5200,
          "deploy_script" => "RAILS/city_app/deploy.sh", "deploy_root" => "RAILS/city_app",
          "public" => true, "deploy_order" => 20,
        },
        "wardrobe_app" => {
          "title" => "Wardrobe App", "domain" => "wardrobe.example.test", "port" => 5300,
          "deploy_script" => "RAILS/wardrobe_app/deploy.sh", "deploy_root" => "RAILS/wardrobe_app",
          "public" => true, "deploy_order" => 30,
        },
        "private_service" => {
          "title" => "Private Service", "domain" => "private.example.test", "port" => 5400,
          "deploy_script" => "RAILS/private_service/deploy.sh", "deploy_root" => "PRIVATE/private_service",
          "public" => false, "deploy_order" => 40,
        },
      }
      File.write(File.join(root, "RAILS", "apps.yml"), YAML.dump("apps" => apps))
      yield root
    end
  end

  def test_public_selection_and_exclusion_resolve_to_a_complete_group
    with_inventory do |root|
      reply = JSON.generate(
        "intent" => "operator_action", "operation" => "deploy", "environment" => "production",
        "target_type" => "public", "target" => "public", "exclude" => ["control_web"],
        "confidence" => 0.94, "reason" => "Public apps except the control interface.",
      )
      agent = FakeAgent.new(reply, [])
      result = Master::CLI::OperatorIntent.new(root:, agent:).call(
        "refresh the public apps, but leave the control interface alone"
      )

      assert_equal :deploy, result.status
      assert_equal "rails", result.target
      assert_equal %w[city_app wardrobe_app], result.selected
      schema = agent.calls.first[:options].fetch(:format)
      assert_equal %w[control_web city_app wardrobe_app private_service],
                   schema.dig(:properties, :exclude, :items, :enum)
      assert_includes agent.calls.first[:prompt], "Wardrobe App"
    end
  end

  def test_pub5_deployment_resolves_to_all_registered_surfaces_without_model_guessing
    with_inventory do |root|
      agent = FakeAgent.new("", [])
      result = Master::CLI::OperatorIntent.new(root:, agent:).call("deploy pub5 to vm23")

      assert_equal :deploy, result.status
      assert_equal "all", result.target
      assert_equal %w[control_web city_app wardrobe_app private_service], result.selected
      assert_empty agent.calls, "the repository alias is deterministic"

      intent = Master::CLI::OperatorIntent.new(root:, agent: Object.new)
      inventory = Deploy::Inventory.new(root:)
      refute intent.send(:repository_wide_deployment?, "deploy pub5 to staging", inventory),
             "explicit non-production environments must not become vm23 deployments"
      refute intent.send(:repository_wide_deployment?, "deploy city_app from pub5 to vm23", inventory),
             "an explicit app target must be left to the inventory classifier"
    end
  end

  def test_unregistered_app_id_is_rejected
    with_inventory do |root|
      reply = JSON.generate(
        "intent" => "operator_action", "operation" => "deploy", "environment" => "production",
        "target_type" => "app", "target" => "not_registered", "exclude" => [],
        "confidence" => 0.99, "reason" => "invented target",
      )
      result = Master::CLI::OperatorIntent.new(root:, agent: FakeAgent.new(reply, [])).call("deploy that application")

      assert_equal :ambiguous, result.status
      assert_includes result.message, "registered app"
    end
  end

  def test_a_partial_selection_that_is_not_a_group_is_ambiguous
    with_inventory do |root|
      reply = JSON.generate(
        "intent" => "operator_action", "operation" => "deploy", "environment" => "production",
        "target_type" => "all", "target" => "all", "exclude" => ["private_service"],
        "confidence" => 0.95, "reason" => "Exclude one service.",
      )
      result = Master::CLI::OperatorIntent.new(root:, agent: FakeAgent.new(reply, [])).call(
        "deploy everything except the private service"
      )

      assert_equal :ambiguous, result.status
      assert_includes result.message, "complete registered deployment group"
    end
  end

  def test_unimplemented_operator_action_is_recognized_but_never_dispatched
    with_inventory do |root|
      reply = JSON.generate(
        "intent" => "operator_action", "operation" => "restart", "environment" => "production",
        "target_type" => "app", "target" => "city_app", "exclude" => [],
        "confidence" => 0.99, "reason" => "A service restart was requested.",
      )
      result = Master::CLI::OperatorIntent.new(root:, agent: FakeAgent.new(reply, [])).call(
        "restart the city service"
      )

      assert_equal :unsupported, result.status
      assert_includes result.message, "not enabled yet"
      assert_includes result.message, "Nothing was run"
    end
  end

  def test_repository_editing_is_not_an_operator_action
    with_inventory do |root|
      reply = JSON.generate(
        "intent" => "conversation", "operation" => "none", "environment" => "unknown",
        "target_type" => "all", "target" => "all", "exclude" => [],
        "confidence" => 0.99, "reason" => "Editing documentation is repository work.",
      )
      result = Master::CLI::OperatorIntent.new(root:, agent: FakeAgent.new(reply, [])).call(
        "update the README to explain the deploy flow"
      )

      assert_equal :conversation, result.status
    end
  end

  def test_non_deploy_requests_remain_conversation
    with_inventory do |root|
      reply = JSON.generate(
        "intent" => "conversation", "operation" => "none", "environment" => "unknown",
        "target_type" => "all", "target" => "all", "exclude" => [],
        "confidence" => 0.98, "reason" => "Asking about deployment concepts.",
      )
      result = Master::CLI::OperatorIntent.new(root:, agent: FakeAgent.new(reply, [])).call("What does deploy mean?")
      assert_equal :conversation, result.status
    end
  end
end
