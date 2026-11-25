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

  # "redeploy MASTER web to vm23" was refused whenever the classifier was down.
  def test_one_named_app_on_vm23_resolves_without_the_model
    with_inventory do |root|
      agent = FakeAgent.new("", [])
      intent = Master::CLI::OperatorIntent.new(root:, agent:)

      result = intent.call("please redeploy Control Web to vm23")
      assert_equal :deploy, result.status
      assert_equal %w[control_web], result.selected
      assert_equal :deploy, intent.call("deploy Wardrobe App on production").status
      assert_empty agent.calls, "a single named app is deterministic"

      inventory = Deploy::Inventory.new(root:)
      ["deploy city_app and wardrobe_app to vm23", "deploy city_app to staging", "deploy city_app",
       "deploy everything except city_app on vm23", "deploy rails to vm23"].each do |text|
        assert_nil intent.send(:single_named_app, text, inventory), text
      end
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
      refute intent.send(:repository_wide_deployment?, "deploy pub5 to dev", inventory),
             "the dev environment must remain distinct from the SSH user dev@host"
      refute intent.send(:repository_wide_deployment?, "deploy city_app from pub5 to vm23", inventory),
             "an explicit app target must be left to the inventory classifier"
      refute intent.send(:repository_wide_deployment?, "how do I deploy pub5 to vm23?", inventory),
             "deployment questions must remain conversational"
      refute intent.send(:repository_wide_deployment?, "deploy pub5 to aws", inventory),
             "an explicit third-party host must not be rewritten to vm23"
      assert intent.send(:repository_wide_deployment?, "please deploy pub5 to production", inventory),
             "an explicit production destination remains deterministic"
      assert intent.send(:repository_wide_deployment?, "redeploy everything on vm23", inventory),
             "everything means the complete registered deployment inventory"
      refute intent.send(:repository_wide_deployment?, "redeploy everything except MASTER/web on vm23", inventory),
             "an exclusion must never silently expand to the full inventory"
      all = Master::CLI::OperatorIntent.new(root:, agent: Object.new).call("redeploy everything on vm23")
      assert_equal :deploy, all.status
      assert_equal "all", all.target
      assert_equal %w[control_web city_app wardrobe_app private_service], all.selected
      assert intent.send(:repository_wide_deployment?, "redeploy OPENBSD, RAILS and MASTER/web to vm23", inventory),
             "the explicit three-part production stack is the canonical full release"
      direct = Master::CLI::OperatorIntent.new(root:, agent: Object.new).call(
        "redeploy OPENBSD, RAILS and MASTER/web to vm23"
      )
      assert_equal :deploy, direct.status
      assert_equal "all", direct.target
      assert_equal %w[control_web city_app wardrobe_app private_service], direct.selected
      assert intent.send(:repository_wide_deployment?, "redeploy OPENBSD, RAILS apps and MASTER web to vm23", inventory),
             "the spaced MASTER web name is the same canonical full release"
      spaced = Master::CLI::OperatorIntent.new(root:, agent: Object.new).call(
        "redeploy OPENBSD, RAILS apps and MASTER web to vm23"
      )
      assert_equal :deploy, spaced.status
      assert_equal "all", spaced.target
      punctuated_request = "Redeploy OPENBSD, RAILS apps and MASTER web to vm23."
      assert intent.send(:repository_wide_deployment?, punctuated_request, inventory),
             "terminal sentence punctuation must not change the destination host"
      assert Master::CLI::OperatorIntent.direct_full_stack_confirmation?(punctuated_request),
             "the exact natural-language command with a final full stop remains confirmed"
      punctuated = Master::CLI::OperatorIntent.new(root:, agent: Object.new).call(punctuated_request)
      assert_equal :deploy, punctuated.status
      assert_equal "all", punctuated.target
      assert_equal %w[control_web city_app wardrobe_app private_service], punctuated.selected
      refute intent.send(:repository_wide_deployment?, "redeploy OPENBSD, RAILS apps and MASTER web to staging", inventory),
             "the spaced full-stack alias must still reject non-production"
      assert intent.send(:repository_wide_deployment?, "redeploy OPENBSD and RAILS to vm23", inventory),
             "the two named deployment layers identify the canonical production release"
      short_stack = Master::CLI::OperatorIntent.new(root:, agent: Object.new).call(
        "redeploy OPENBSD and RAILS to vm23"
      )
      assert_equal :deploy, short_stack.status
      assert_equal "all", short_stack.target
      assert_equal %w[control_web city_app wardrobe_app private_service], short_stack.selected
      refute intent.send(:repository_wide_deployment?, "redeploy OPENBSD, RAILS and MASTER/web to staging", inventory),
             "an explicit non-production destination must remain unsupported"
    end
  end

  def test_operator_wording_for_the_complete_pub5_release_is_deterministic
    with_inventory do |root|
      requests = [
        "you need to deploy pub5 onto vm23",
        "i want you to deploy OPENBSD and MASTER and RAILS to vm23 (ssh dev@brgen.no, wheel group)",
        "Can you redeploy all our apps on vm23?",
        "Please redeploy all of our apps on vm23.",
      ]

      requests.each do |message|
        assert Master::CLI::OperatorIntent.direct_deploy_request?(message), message
        assert Master::CLI::OperatorIntent.direct_full_stack_confirmation?(message), message

        agent = Object.new
        result = Master::CLI::OperatorIntent.new(root:, agent:).call(message)

        assert_equal :deploy, result.status, message
        assert_equal "all", result.target, message
        assert_equal %w[control_web city_app wardrobe_app private_service], result.selected
      end
    end
  end

  def test_analysis_first_compound_request_bypasses_the_operator_classifier
    with_inventory do |root|
      message = "analyze OPENBSD and MASTER and RAILS folders recursively, and then ssh to vm23, git pull, and deploy these on the actual production system"
      agent = Object.new
      intent = Master::CLI::OperatorIntent.new(root:, agent:)

      assert Master::CLI::OperatorIntent.source_analysis_first?(message)
      refute Master::CLI::OperatorIntent.direct_full_stack_confirmation?(message)

      result = intent.call(message)
      assert_equal :conversation, result.status
    end
  end

  def test_questions_negations_and_partial_scopes_are_not_execution_confirmation
    [
      "How do I analyze OPENBSD MASTER and RAILS, then deploy them on vm23?",
      "Do not analyze OPENBSD MASTER and RAILS, then deploy on vm23",
      "analyze OPENBSD and RAILS, then deploy on vm23",
    ].each do |message|
      refute Master::CLI::OperatorIntent.source_analysis_first?(message), message
      refute Master::CLI::OperatorIntent.direct_full_stack_confirmation?(message), message
    end
  end

  def test_full_release_includes_studio_source_without_inventing_a_service
    with_inventory do |root|
      agent = Object.new
      message = "please redeploy OPENBSD, RAILS, STUDIO, and MASTER/web on vm23"

      assert Master::CLI::OperatorIntent.direct_full_stack_confirmation?(message)
      result = Master::CLI::OperatorIntent.new(root:, agent:).call(message)

      assert_equal :deploy, result.status
      assert_equal "all", result.target
      assert_equal %w[control_web city_app wardrobe_app private_service], result.selected
    end
  end

  def test_studio_only_request_remains_unsupported
    with_inventory do |root|
      result = Master::CLI::OperatorIntent.new(root:, agent: Object.new).call(
        "please redeploy STUDIO on vm23"
      )

      assert_equal :unsupported, result.status
      assert_includes result.message, "STUDIO source is included in the pinned pub5 checkout"
      assert_includes result.message, "no independent vm23 runtime target"
    end
  end

  def test_greeted_polite_question_form_resolves_exact_full_stack_without_model_guessing
    with_inventory do |root|
      message = "Hey, can you redeploy OPENBSD, RAILS, and MASTER web on vm23 please?"
      agent = Object.new

      assert Master::CLI::OperatorIntent.direct_deploy_request?(message)
      assert Master::CLI::OperatorIntent.direct_full_stack_confirmation?(message)

      result = Master::CLI::OperatorIntent.new(root:, agent:).call(message)

      assert_equal :deploy, result.status
      assert_equal "all", result.target
      assert_equal %w[control_web city_app wardrobe_app private_service], result.selected
    end
  end

  def test_stacked_politeness_prefixes_keep_explicit_deploys_deterministic
    with_inventory do |root|
      messages = [
        "Hey, could you please redeploy OPENBSD, RAILS, and MASTER web on vm23?",
        "Please, can you redeploy everything on vm23?",
        "I need you to please redeploy OPENBSD, RAILS, and MASTER web on vm23.",
        "ok, now, you gotta redeploy MASTER, RAILS, OPENBSD onto vm23 properly, and ensure vm23 is in good health",
      ]

      messages.each do |message|
        assert Master::CLI::OperatorIntent.direct_deploy_request?(message), message
        assert Master::CLI::OperatorIntent.direct_full_stack_confirmation?(message), message
        result = Master::CLI::OperatorIntent.new(root:, agent: Object.new).call(message)
        assert_equal :deploy, result.status, message
        assert_equal "all", result.target, message
      end

      refute Master::CLI::OperatorIntent.direct_deploy_request?(
        "Could you please explain how to redeploy the full stack on vm23?"
      )
    end
  end

  def test_plan_only_request_stays_conversational_without_classifier_or_deployment
    with_inventory do |root|
      agent = Object.new
      result = Master::CLI::OperatorIntent.new(root:, agent:).call(
        "Prepare a deployment plan ONLY for redeploying OPENBSD, RAILS and MASTER/web to vm23"
      )

      assert_equal :plan_only, result.status
    end
  end

  def test_classifier_failure_reports_error_class_without_running_an_action
    with_inventory do |root|
      agent = Object.new
      agent.define_singleton_method(:ask_once) { |*| raise JSON::ParserError, "provider payload detail" }
      result = Master::CLI::OperatorIntent.new(root:, agent:).call("deploy the city application")

      assert_equal :unavailable, result.status
      assert_includes result.message, "JSON::ParserError"
      refute_includes result.message, "provider payload detail"
      assert_includes result.message, "diagnostic"
      assert_includes result.message, "no action was taken"
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

  # A schema-less provider drops empty fields: the request "deploy everything"
  # has no exclusions, so the model omits the key. Absent means none.
  def test_a_missing_exclude_defaults_to_no_exclusions
    with_inventory do |root|
      reply = JSON.generate(
        "intent" => "operator_action", "operation" => "deploy", "environment" => "production",
        "target_type" => "app", "target" => "city_app",
        "confidence" => 0.97, "reason" => "One named app.",
      )
      # Not one plainly named app, so the reply contract is what decides.
      result = Master::CLI::OperatorIntent.new(root:, agent: FakeAgent.new(reply, [])).call(
        "deploy the town application to vm23"
      )

      assert_equal :deploy, result.status
      assert_equal ["city_app"], result.selected
    end
  end

  def test_unknown_fields_still_fail_closed
    with_inventory do |root|
      reply = JSON.generate(
        "intent" => "operator_action", "operation" => "deploy", "environment" => "production",
        "target_type" => "app", "target" => "city_app", "exclude" => [],
        "confidence" => 0.97, "reason" => "One named app.", "confirm" => true,
      )
      # Not one plainly named app, so the reply contract is what decides.
      result = Master::CLI::OperatorIntent.new(root:, agent: FakeAgent.new(reply, [])).call(
        "deploy the town application to vm23"
      )

      assert_equal :unavailable, result.status
    end
  end

  def test_a_missing_confidence_still_fails_closed
    with_inventory do |root|
      reply = JSON.generate(
        "intent" => "operator_action", "operation" => "deploy", "environment" => "production",
        "target_type" => "app", "target" => "city_app",
        "reason" => "Confidence omitted entirely.",
      )
      # Not one plainly named app, so the reply contract is what decides.
      result = Master::CLI::OperatorIntent.new(root:, agent: FakeAgent.new(reply, [])).call(
        "deploy the town application to vm23"
      )

      assert_equal :unavailable, result.status
    end
  end

  def test_all_rails_apps_plus_master_web_is_a_deterministic_full_release
    with_inventory do |root|
      message = "deploy all Rails apps plus MASTER web to vm23"
      result = Master::CLI::OperatorIntent.new(root:, agent: Object.new).call(message)

      assert Master::CLI::OperatorIntent.direct_full_stack_confirmation?(message)
      assert_equal :deploy, result.status
      assert_equal "all", result.target
      assert_equal %w[control_web city_app wardrobe_app private_service], result.selected
    end
  end

  def test_production_full_release_includes_every_active_rails_app_and_master_web
    repository_root = File.dirname(Master::ROOT)
    inventory = Deploy::Inventory.new(root: repository_root)
    expected = %w[amber brgen bsdports master mrdamascy]
    assert_equal expected, inventory.app_names.sort
    master = inventory.apps.find { |app| app.name == "master" }
    assert_equal "MASTER/web", master.deploy_root

    message = "deploy all Rails apps plus MASTER web to vm23"
    result = Master::CLI::OperatorIntent.new(root: Master::ROOT, agent: Object.new).call(message)
    assert_equal :deploy, result.status
    assert_equal "all", result.target
    assert_equal inventory.ordered_apps.map(&:name), result.selected
  end

end
