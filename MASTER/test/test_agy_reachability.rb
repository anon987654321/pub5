# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"
require "rbconfig"

# agy is the only entry in the routing tables that is not an API model. It is
# the Antigravity CLI, reached by executing a binary, and two things about it
# have to stay true no matter how the tiers are ordered:
#
#   1. It is never offered when the binary is not there. An id that can only be
#      failed over is not a route.
#   2. When present, it is available at its declared position in the model
#      tiers. Earlier configured models keep their lead; observed quota/failure
#      moves the router to the next configured lane without special promotion.
#
# data/models.yml carries agy:auto in default and primary, while the live
# `agy models` catalogue feeds additional agy:<model> fallback members.
#
# The shape this hid behind: MASTER_NO_AGY_CLI existed and both
# agy_cli_available? methods honoured it, so the guard looked complete while the
# ids arrived by paths that never asked. test_keyless_routing.rb neutralises
# both CLIs for the same reason; this file is where agy's own routing is graded.
class TestAgyReachability < Minitest::Test
  FakeConfig = Master::TestSupport::FakeConfig
  GUARDED = %w[
    XAI_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY
    DEEPSEEK_API_KEY GOOGLE_API_KEY GEMINI_API_KEY MISTRAL_API_KEY
    MASTER_KEYLESS MASTER_WEB_CHAT MASTER_NO_GROK_CLI MASTER_NO_AGY_CLI AGY_BIN
  ].freeze
  OPENROUTER_KEY = "sk-or-v1-#{"a" * 64}"
  AGY = /\Aagy(?::|\z)/

  def setup
    @saved = GUARDED.to_h { |key| [key, ENV[key]] }
    GUARDED.each { |key| ENV.delete(key) }
    ENV["MASTER_NO_GROK_CLI"] = "1"
  end

  def teardown
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_agy(available)
    if available
      # A file that exists and is executable is what both lookups accept, and
      # AGY_BIN is the first thing either of them reads.
      ENV.delete("MASTER_NO_AGY_CLI")
      ENV["AGY_BIN"] = agy_stub
    else
      ENV["MASTER_NO_AGY_CLI"] = "1"
    end
    yield
  end

  def agy_stub
    @agy_stub ||= begin
      path = File.join(Dir.mktmpdir("agy"), "agy")
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
      path
    end
  end

  def router
    r = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: "x"), root: Master::ROOT)
    # The pool grows from `agy models`; a machine without the binary answers
    # with an empty listing and the chain contract under test never sees agy.
    # Pin the listing instead of the machine.
    r.define_singleton_method(:run_probe) { |*_command, **_k| "gemini-3.1-pro-high\nauto\n" }
    r
  end

  # The availability contract is tested on code generation, where the
  # first reachable entry in the configured task tier should lead.
  # Exploration is explicitly a free route.
  def chain
    router.fallback_chain(task_type: :code_generation)
  end

  # --- 1. never offered when the binary is absent --------------------------

  def test_default_model_does_not_name_agy_when_the_binary_is_absent
    ENV["OPENROUTER_API_KEY"] = OPENROUTER_KEY
    with_agy(false) do
      refute_match AGY, Master.default_model,
                   "default_model named the Antigravity CLI on a machine that has no agy binary"
    end
  end

  def test_the_fallback_chain_offers_no_agy_when_the_binary_is_absent
    ENV["OPENROUTER_API_KEY"] = OPENROUTER_KEY
    with_agy(false) do
      offered = chain

      assert_empty offered.grep(AGY), "the chain offered agy models on a machine with no agy binary"
      refute_empty offered, "dropping agy emptied the chain"
    end
  end

  # The same with no key at all, since that is the path where agy is the
  # intended answer and so the one most likely to hand back an absent binary.
  def test_nothing_names_agy_with_neither_a_key_nor_a_binary
    with_agy(false) do
      refute_match AGY, Master.default_model
      assert_empty chain.grep(AGY)
    end
  end

  # --- 2. present, but behind a configured key -----------------------------

  def test_agy_is_the_default_when_it_is_there_and_no_key_is
    with_agy(true) do
      assert_match AGY, Master.default_model,
                   "with no API key and the binary present, agy is the route that exists"
    end
  end

  def test_agy_remains_available_after_the_declared_primary_when_an_api_key_is_configured
    ENV["OPENROUTER_API_KEY"] = OPENROUTER_KEY
    with_agy(true) do
      assert_match AGY, Master.default_model,
                   "AGY remains eligible without promoting itself over earlier configured tier entries"
      assert_match AGY, chain.first,
                   "AGY remains in the fallback chain when its binary is present"
    end
  end

  # API routes remain available beside and ahead of AGY according to their
  # declared tier position; AGY availability never replaces a configured head.
  def test_api_routes_remain_available_alongside_agy
    ENV["OPENROUTER_API_KEY"] = OPENROUTER_KEY
    with_agy(true) do
      refute_empty chain.reject { |id| id.match?(AGY) },
                   "API/local/free fallback lanes disappeared"
    end
  end

  # --- the instrument itself ----------------------------------------------

  # Every assertion above rests on the stub being taken for a real binary. If
  # that stopped working, the absence half would pass for the wrong reason.
  def test_parse_agy_models_accepts_official_slug_rows
    router_instance = router
    output = <<~TEXT
      gemini-3.8-flash-high     Gemini 3.8 Flash (High)
      gemini-3.8-flash-medium   Gemini 3.8 Flash (Medium)
      gemini-3.1-pro-high       Gemini 3.1 Pro (High)
      Claude Sonnet 4.6 (Thinking)
      Weekly Limit Remaining
    TEXT

    assert_equal %w[gemini-3.8-flash-high gemini-3.8-flash-medium gemini-3.1-pro-high],
                 router_instance.send(:parse_agy_models, output)
  end

  def test_the_stub_is_actually_detected
    with_agy(true) { assert Master.agy_cli_available?, "the agy stub was not detected as available" }
    with_agy(false) { refute Master.agy_cli_available? }
  end

  def test_probe_deadline_includes_grandchildren_holding_output_open
    router_instance = Master::CLI::Routing::ModelRouter.allocate
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    output = router_instance.send(
      :run_probe, RbConfig.ruby, "-e", "fork { sleep 5 }; exit 0", timeout: 0.2
    )

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_nil output, "a probe with a surviving child must be inconclusive"
    assert_operator elapsed, :<, 3.0, "a grandchild-held pipe must not defeat the probe deadline"
  end
end
