# frozen_string_literal: true

require_relative "test_helper"

class TestOpenhandsSandbox < Minitest::Test
  Sandbox = Master::Ground::OpenhandsSandbox

  # A fresh hash per case keeps the assertions off the process environment.
  def sandbox_env(overrides = {})
    { "OH_INTERNAL_SERVER_URL" => "http://127.0.0.1:60000", "SESSION_API_KEY" => "session-key" }.merge(overrides)
  end

  def test_wires_gateway_from_the_sandbox_endpoint
    env = sandbox_env
    assert_equal "http://127.0.0.1:60000/v1", Sandbox.wire!(env)
    assert_equal "http://127.0.0.1:60000/v1", env["MASTER_LLM_GATEWAY_URL"]
    assert_equal "session-key", env["MASTER_LLM_GATEWAY_KEY"]
    assert_equal "1", env["MASTER_LLM_GATEWAY_FOLD_SYSTEM"]
  end

  def test_trailing_slash_is_normalized
    env = sandbox_env("OH_INTERNAL_SERVER_URL" => "http://127.0.0.1:60000/")
    assert_equal "http://127.0.0.1:60000/v1", Sandbox.wire!(env)
  end

  def test_an_operator_gateway_is_left_untouched
    env = sandbox_env("MASTER_LLM_GATEWAY_URL" => "https://gateway.example/v1")
    assert_nil Sandbox.wire!(env)
    assert_equal "https://gateway.example/v1", env["MASTER_LLM_GATEWAY_URL"]
    refute env.key?("MASTER_LLM_GATEWAY_KEY")
  end

  def test_no_sandbox_endpoint_wires_nothing
    env = { "SESSION_API_KEY" => "session-key" }
    assert_nil Sandbox.wire!(env)
    refute env.key?("MASTER_LLM_GATEWAY_URL")
  end

  def test_no_session_key_wires_nothing
    env = { "OH_INTERNAL_SERVER_URL" => "http://127.0.0.1:60000" }
    assert_nil Sandbox.wire!(env)
    refute env.key?("MASTER_LLM_GATEWAY_URL")
  end

  def test_explicit_opt_out_disables_wiring
    env = sandbox_env("MASTER_NO_SANDBOX_GATEWAY" => "1")
    assert_nil Sandbox.wire!(env)
    refute env.key?("MASTER_LLM_GATEWAY_URL")
  end

  def test_empty_state_flag_disables_wiring
    env = sandbox_env("MASTER_NO_ENV_FILES" => "1")
    assert_nil Sandbox.wire!(env)
    refute env.key?("MASTER_LLM_GATEWAY_URL")
  end

  def test_fold_flag_is_not_overwritten_when_already_set
    env = sandbox_env("MASTER_LLM_GATEWAY_FOLD_SYSTEM" => "0")
    Sandbox.wire!(env)
    assert_equal "0", env["MASTER_LLM_GATEWAY_FOLD_SYSTEM"]
  end

  def test_the_relayed_agent_server_gets_a_wider_read_idle_budget
    env = sandbox_env
    Sandbox.wire!(env)

    assert_equal Sandbox::READ_IDLE_S, env["MASTER_LLM_READ_IDLE_S"]
  end

  def test_an_operator_read_idle_budget_is_left_untouched
    env = sandbox_env("MASTER_LLM_READ_IDLE_S" => "45")
    Sandbox.wire!(env)

    assert_equal "45", env["MASTER_LLM_READ_IDLE_S"]
  end
end
