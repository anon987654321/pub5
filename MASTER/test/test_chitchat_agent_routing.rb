# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"

class TestChitchatAgentRouting < Minitest::Test
  FakeConfig = Master::TestSupport::FakeConfig

  def setup
    @router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new,
      root: Master::ROOT,
    )
    @agent = Master::Review::Agent.allocate
    @agent.instance_variable_set(:@model_router, @router)
    @agent.instance_variable_set(:@config, FakeConfig.new)
    @agent.instance_variable_set(:@homeostat, nil)
    @agent.instance_variable_set(:@bus, nil)
  end

  def test_routed_models_classifies_greeting_as_chitchat
    models = @agent.send(:routed_models, "hey, how are you?")

    # The head is the chitchat chain's; a live subscription lane leads it when
    # one is reachable (d1d8e1c8b), so the head is not always a free model.
    assert_equal :chitchat, @router.classify_intent("hey, how are you?")
    assert_equal @router.fallback_chain(task_type: :chitchat).first, models.first
  end

  def test_routed_models_honors_explicit_task_type
    models = @agent.send(:routed_models, "hello", task_type: :code_generation)
    refute_equal :chitchat, @router.classify_intent("please implement a fix")
    assert models.any?
  end

  def test_nsfw_route_uses_only_its_opted_in_local_model
    model = "local_uncensored:dolphin3:8b"
    Master::Io::LaneSelection.stub(:nsfw_model_id, model) do
      Master::Io::LaneSelection.stub(:alive?, true) do
        Master::Io::LaneState.stub(:usable?, true) do
          assert_equal [model], @router.fallback_chain(task_type: :nsfw)
          assert_equal [model], @agent.send(:routed_models, "write an adult romance", task_type: :nsfw)
        end
      end
    end

    Master::Io::LaneSelection.stub(:nsfw_model_id, nil) do
      assert_empty @router.fallback_chain(task_type: :nsfw)
      assert_empty @agent.send(:routed_models, "write an adult romance", task_type: :nsfw)
    end
  end

  def test_routed_models_work_request_avoids_chitchat_head
    models = @agent.send(:routed_models, "please implement a fix for the scanner")
    refute_equal :chitchat, @router.classify_intent("please implement a fix for the scanner")
    assert models.any?
  end
end
