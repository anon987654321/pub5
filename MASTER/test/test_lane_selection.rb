# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/agent"
require "tmpdir"
require "tempfile"
require_relative "support_council_answer"

# One rule picks the model for every /fix and council call: the tier's models in
# data/models.yml order, dead lanes dropped (quota, silence, the hand-kept list),
# free models last. Each test that claims the rule is reached counts the calls
# that arrive at it, so a green run cannot mean the code sits unused.
class TestLaneSelection < Minitest::Test
  Selection = Master::Io::LaneSelection
  Quota = Master::Io::LaneQuota

  OPUS = "claude-cli:claude-opus-5-5"
  SONNET = "claude-cli:claude-sonnet-5-5"
  GLM = "glm-5.3"
  GROK = "grok-cli:auto"
  AGY = "agy:auto"
  LOCAL = "ollama:gemma3:4b"
  LLAMA_LOCAL = "llama-cli:gguf"
  NEMOTRON = "nvidia/nemotron-3-super-120b-a12b:free"
  NANO = "nvidia/nemotron-3.5-lightning:free"
  LLM7 = "llm7:DeepSeek-V4-Flash-0731"
  DEEPSEEK = "deepseek-chat"
  AGY_REPLY = "agy: error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 165h22m49s."
  GLM_REPLY = "glm: error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 49h10m05s."
  CLAUDE_REPLY = "You've hit your session limit - resets 5pm (Europe/Oslo)"
  ALL = ->(_model) { true }
  NOON = Time.utc(2026, 10, 11, 12, 0, 0).to_f

  # models.yml is parsed once per change and handed out frozen; an edit is seen on the next read.
  def test_the_models_file_is_read_again_only_when_it_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "models.yml")
      File.write(path, "models:\n  default:\n    - id: a\n")
      first = Selection.config(path)

      assert_same first, Selection.config(path)
      assert_predicate first.dig("models", "default"), :frozen?

      File.write(path, "models:\n  default:\n    - id: a\n    - id: b\n")
      assert_equal %w[a b], Selection.tier("default", cfg: Selection.config(path))
    end
  end

  def setup
    Selection.reset_hosted_resolver!
    @saved_ollama_enabled = ENV["MASTER_OLLAMA_ENABLED"]
    @saved_no_ollama = ENV["MASTER_NO_OLLAMA"]
    ENV.delete("MASTER_NO_OLLAMA")
    ENV["MASTER_OLLAMA_ENABLED"] = "1"
    @dir = Dir.mktmpdir
    Quota.path = File.join(@dir, "lane_quota.yml")
    Quota.clock = -> { NOON }
  end

  def teardown
    Quota.path = nil
    Quota.clock = -> { Time.now.to_f }
    @saved_ollama_enabled.nil? ? ENV.delete("MASTER_OLLAMA_ENABLED") : ENV["MASTER_OLLAMA_ENABLED"] = @saved_ollama_enabled
    @saved_no_ollama.nil? ? ENV.delete("MASTER_NO_OLLAMA") : ENV["MASTER_NO_OLLAMA"] = @saved_no_ollama
    Selection.reset_hosted_resolver!
    FileUtils.remove_entry(@dir)
  end

  # Use a fixed hosted index so routing policy tests do not depend on a live
  # provider /models endpoint, its cache, or the machine's network.
  def with_hosted_models(ids, keyless: false)
    resolver = Object.new
    resolver.define_singleton_method(:hosted_models) { ids }
    resolver.define_singleton_method(:hosted_endpoint_for) do |model|
      next unless ids.include?(model)

      spec = Selection.config.dig("openai_compatible", Selection.provider(model)) || {}
      key = if keyless
        nil
      else
        Array(spec["key_env"]).filter_map { |name| ENV[name] }.find { |value| !value.empty? }
      end
      { key: }
    end
    Selection.stub(:hosted_resolver, resolver) { yield }
  end

  # Counts every call that reaches the selection function while the block runs.
  def counting(method_name)
    calls = []
    original = Selection.method(method_name)
    Selection.define_singleton_method(method_name) { |*args, **kw, &blk| calls << args; original.call(*args, **kw, &blk) }
    yield calls
  ensure
    Selection.singleton_class.send(:remove_method, method_name)
  end

  def test_ollama_stays_out_of_the_pool_until_explicitly_enabled
    ENV.delete("MASTER_OLLAMA_ENABLED")
    refute Selection.ollama_enabled?
    assert_empty Selection.order([LOCAL])
    assert_empty Selection.order_or_all([LOCAL]), "a disabled local lane must not be resurrected"

    ENV["MASTER_OLLAMA_ENABLED"] = "1"
    assert Selection.ollama_enabled?, "the operator can deliberately restore the local lane"

    ENV["MASTER_NO_OLLAMA"] = "1"
    refute Selection.ollama_enabled?, "the hard-off switch still overrides the opt-in"
    assert_empty Selection.order([LOCAL])
    assert_empty Selection.order_or_all([LOCAL])
  end

  def test_zero_key_probe_serves_a_reachable_local_brain_only_without_keys
    ENV.delete("MASTER_OLLAMA_ENABLED")
    cfg = { "ollama" => { "probe" => true, "default_base_url" => "http://localhost:11434" } }
    probe = Selection.method(:zero_key_probe?)
    Selection.stub(:api_listening?, true) do
      Selection.instance_variable_set(:@zero_key_probe, nil)
      Master.stub(:any_api_key_present?, false) do
        assert probe.call(cfg), "no key anywhere: the local brain is the default"
      end
      Selection.instance_variable_set(:@zero_key_probe, nil)
      Master.stub(:any_api_key_present?, true) do
        refute probe.call(cfg), "a configured key leaves the remote lanes standing"
      end
    end
  end

  def test_zero_key_probe_is_refused_by_switch_and_arm_and_unreachable_daemon
    ENV.delete("MASTER_OLLAMA_ENABLED")
    ENV["MASTER_NO_OLLAMA"] = "1"
    refute Selection.ollama_enabled?
    ENV.delete("MASTER_NO_OLLAMA")

    probe = Selection.method(:zero_key_probe?)
    Selection.stub(:api_listening?, false) do
      Selection.instance_variable_set(:@zero_key_probe, nil)
      Master.stub(:any_api_key_present?, false) do
        refute probe.call({ "ollama" => { "probe" => true } }), "no daemon, no default"
      end
    end
    Selection.stub(:api_listening?, false) do
      Selection.instance_variable_set(:@zero_key_probe, nil)
      Master.stub(:any_api_key_present?, false) do
        refute probe.call({ "ollama" => { "probe" => true, "default_base_url" => "http://localhost:99999" } }),
               "an explicit probe arm is still the only arm"
        refute probe.call({ "ollama" => {} }), "nothing armed, nothing probed"
      end
    end
  end

  def test_first_live_of_the_tier_skips_a_quota_dead_lane
    tier = [AGY, OPUS, GROK, NEMOTRON]
    assert_equal OPUS, Selection.first_live(tier), "claude-cli leads the subscription lanes whatever order the list came in"

    Quota.note(AGY, AGY_REPLY)
    assert_equal OPUS, Selection.first_live(tier)

    Quota.note(OPUS, CLAUDE_REPLY)
    assert_equal GROK, Selection.first_live(tier)
  end

  def test_the_real_default_tier_keeps_subscription_lead_and_glm_lists_first
    tier = Selection.tier("default")
    assert_equal GLM, tier.first, "models.yml lists glm-5.3 first in the default tier (operator, 2026-11-09)"
    # The selection sort is a contract of its own: a live subscription lane
    # leads whatever the file order came in as, and a metered-API lane with
    # no key on the host drops out of the live list entirely.
    assert_equal OPUS, Selection.first_live(tier)

    Quota.note(OPUS, CLAUDE_REPLY)
    assert_equal AGY, Selection.first_live(tier), "the claude-cli lane is dead as a whole, sonnet with opus"
    ordered = Selection.order(tier)
    kinds = ordered.map { |id| Selection.kind(id) }
    assert_equal kinds.sort_by { |k| Selection::KIND_RANK.fetch(k) }, kinds, "remote, then local, then free"
    refute_includes ordered, OPUS

    primary = Selection.tier("primary")
    assert_equal GLM, primary.first, "the primary /fix lane stays glm-5.3 (operator, 2026-11-09)"
  end

  def test_free_models_come_last_whatever_the_given_order
    mixed = [NEMOTRON, NANO, LOCAL, DEEPSEEK, GROK]
    assert_equal [GROK, DEEPSEEK, LOCAL, NEMOTRON, NANO], Selection.order(mixed), "a subscription CLI precedes a metered API key"
    assert_equal [NEMOTRON, NANO, LOCAL, DEEPSEEK, GROK], Selection.order(mixed, free_last: false), "a free route keeps its order"
  end

  def test_llm7_hosted_turbo_models_are_ranked_in_the_free_class
    with_hosted_models([LLM7], keyless: true) do
      assert_equal :free, Selection.kind(LLM7)
      assert_equal [DEEPSEEK, LLM7], Selection.order([LLM7, DEEPSEEK])
    end
  end

  def test_vision_review_order_uses_human_preference_after_capability_filtering
    models = ["gpt-6.1-sol", "gemini-3.7-flash", "qwen3.8-max", OPUS, "text-only"]
    expected = [OPUS, "qwen3.8-max", "gemini-3.7-flash", "gpt-6.1-sol"]
    Selection.stub(:vision?, ->(id) { id != "text-only" }) do
      Master::Io::LaneQuota.stub(:dead?, ->(*_args, **_kwargs) { false }) do
        Master::Io::LaneState.stub(:usable?, ->(*_args, **_kwargs) { true }) do
          assert_equal expected, Selection.vision_rank_order(models)
          assert_equal expected + ["text-only"], Selection.order(models, free_last: false, vision: true)
          assert_equal expected + ["text-only"], Selection.ranked_order(models, free_last: false, vision: true)
        end
      end
    end
  end

  def test_live_keyless_hosted_models_enter_the_boot_catalogue_and_are_alive
    resolver = Object.new
    ids = %w[llm7:gpt-oss:20b ovh:gpt-oss-120b pollinations:openai-fast]
    resolver.define_singleton_method(:hosted_models) { ids }
    resolver.define_singleton_method(:hosted_endpoint_for) { |id| ids.include?(id) ? { key: nil } : nil }

    Selection.stub(:hosted_resolver, resolver) do
      assert_equal ids, Selection.hosted_models
      assert_includes Selection.catalogue, "llm7:gpt-oss:20b"
      assert_includes Selection.catalogue, "ovh:gpt-oss-120b"
      ids.each do |id|
        assert Selection.alive?(id), "#{id} should be alive without a provider key"
        assert_equal :free, Selection.kind(id), "#{id} belongs to the keyless free class"
      end
    end
  end

  def test_llama_cpp_cli_is_local_and_stays_after_remote_lanes
    assert_equal :local, Selection.kind(LLAMA_LOCAL)
    assert_equal [OPUS, DEEPSEEK, LLAMA_LOCAL, NEMOTRON],
                 Selection.order([NEMOTRON, LLAMA_LOCAL, DEEPSEEK, OPUS])
  end

  def test_llama_cpp_cli_requires_a_readable_explicit_model_file
    old_path = ENV["MASTER_LLAMA_MODEL"]
    ENV.delete("MASTER_LLAMA_MODEL")
    refute Selection.local_cli_model_available?(LLAMA_LOCAL)

    Tempfile.create(["master-local-model", ".gguf"]) do |model|
      ENV["MASTER_LLAMA_MODEL"] = model.path
      assert Selection.local_cli_model_available?(LLAMA_LOCAL)
    end
  ensure
    old_path.nil? ? ENV.delete("MASTER_LLAMA_MODEL") : ENV["MASTER_LLAMA_MODEL"] = old_path
  end

  def test_an_explicit_measured_lead_is_preserved_inside_the_subscription_tier
    assert_equal [GROK, OPUS], Selection.order_or_all([OPUS, GROK], lead: [GROK, OPUS])
  end

  def test_subscription_lanes_lead_in_claude_grok_agy_order_ahead_of_api_keys
    assert_equal [OPUS, GROK, AGY, DEEPSEEK, LOCAL, NEMOTRON], Selection.order([NEMOTRON, DEEPSEEK, AGY, GROK, LOCAL, OPUS])
  end

  def test_browser_websites_have_independent_provider_identity
    assert_equal "web-chat:grok", Selection.provider("web-chat:grok")
    assert_equal "web-chat:chatgpt", Selection.provider("web-chat:chatgpt")
    refute_equal Selection.provider("web-chat:grok"), Selection.provider("web-chat:chatgpt")
  end

  def test_the_boot_choice_is_the_first_live_lane_and_names_its_source
    assert_equal [OPUS, "availability"], Selection.boot_choice(env: {}, saved: nil, alive: ALL)
    assert_equal [AGY, "MASTER_MODEL"], Selection.boot_choice(env: { "MASTER_MODEL" => AGY }, saved: nil, alive: ALL)

    sonnet = "claude-cli:claude-sonnet-5-5"
    assert_equal [sonnet, "saved preference"], Selection.boot_choice(env: {}, saved: sonnet, alive: ALL)
    assert_equal [OPUS, "availability"], Selection.boot_choice(env: {}, saved: NEMOTRON, alive: ALL), "a saved free model never leads a live subscription"

    Quota.note(OPUS, CLAUDE_REPLY)
    assert_equal [GROK, "availability"], Selection.boot_choice(env: {}, saved: sonnet, alive: ALL), "a dead preference is not tried"
  end

  def test_announce_lists_only_lanes_available_on_this_machine
    cfg = {
      "models" => {
        "default" => [{ "id" => OPUS }, { "id" => GROK }],
        "strong" => [],
        "local" => [],
      },
    }
    messages = []

    live = Master::Trace::Dmesg.stub(:status, ->(unit, message, **) { messages << [unit, message] }) do
      Selection.announce(cfg:, alive: ->(model) { model == GROK })
    end

    assert_equal [GROK], live
    selection_line = messages.find { |unit, message| unit == "lane0" && message.start_with?("selection order:") }
    refute_nil selection_line
    assert_includes selection_line.last, GROK
    refute_includes selection_line.last, OPUS
  end

  def test_the_primary_report_names_the_lane_and_why
    Quota.note(AGY, AGY_REPLY)
    assert_match(/\Aprimary: #{Regexp.escape(OPUS)} \(first live lane by availability.*; dead: agy/, Selection.primary_report(env: {}, alive: ALL))
    assert_match(/pinned \(MASTER_MODEL\), no failover/,
                 Selection.primary_report(env: { "MASTER_MODEL" => GROK }, alive: ALL))
    assert_match(/pinned \(MASTER_MODEL\), failover on/,
                 Selection.primary_report(env: { "MASTER_MODEL" => GROK, "MASTER_MODEL_STRICT" => "0" }, alive: ALL))
  end

  def test_a_free_class_lane_warns_once_while_a_live_lane_exists
    Selection.watch_free_class!
    Selection.note_provider_outcome(OPUS, :success, alive: ALL)
    warning = Selection.free_class_warning(NEMOTRON, :file_write, alive: ALL)
    assert_match(/WARNING free-class lane #{Regexp.escape(NEMOTRON)} used for file_write while claude-cli:claude-opus-5-5 is live/, warning)
    assert_nil Selection.free_class_warning(NEMOTRON, :file_write, alive: ALL), "once per lane"
    assert_nil Selection.free_class_warning(OPUS, :file_write, alive: ALL), "a subscription lane never warns"
  ensure
    Selection.watch_free_class!(false)
  end

  def test_the_savior_is_a_lane_the_stores_cannot_refuse
    # gemini-2.5-flash is dead by hand in data/lanes.yml, yet alive? reads only
    # binaries and provider keys - so 2026-11-07's walk named it "live" in every
    # free-class warning and the suspension while the wheel kept paying each
    # dead free slug its call. The savior must survive LaneState's verdict.
    Selection.watch_free_class!
    assert_nil Selection.free_class_warning(NEMOTRON, :file_write, alive: ALL),
               "configuration and a visible CLI binary are not successful-completion evidence"
    Selection.note_provider_outcome(OPUS, :success, alive: ALL)
    warning = Selection.free_class_warning(NEMOTRON, :file_write, alive: ALL).to_s
    refute_match(/gemini/, warning, "a hand-dead lane is never named as the lane that takes the work")
    assert_match(/while claude-cli:claude-opus-5-5 is live/, warning, "the savior must have answered this run and remain usable")
  ensure
    Selection.watch_free_class!(false)
  end

  def test_the_suspension_names_a_usable_savior
    Selection.watch_free_class!

    3.times { Selection.note_provider_outcome(NEMOTRON, :failure, alive: ALL) }

    refute_predicate Selection, :free_floor_suspended?, "a configured alternate has not proved it can answer"
    Selection.note_provider_outcome(OPUS, :success, alive: ALL)

    assert_predicate Selection, :free_floor_suspended?, "a real non-free completion can carry the floor"
    chosen = Selection.live_savior(alive: ALL)
    assert_equal OPUS, chosen, "the suspension names a lane no store refuses"
  ensure
    Selection.watch_free_class!(false)
  end

  def test_a_lane_probe_on_a_free_lane_is_not_a_warning
    Selection.watch_free_class!
    Selection.note_provider_outcome(OPUS, :success, alive: ALL)

    assert_nil Selection.free_class_warning(NEMOTRON, :lane_probe, alive: ALL)
    refute_nil Selection.free_class_warning(NEMOTRON, :structural_review, alive: ALL), "the probe used up no warning"
  ensure
    Selection.watch_free_class!(false)
  end

  def test_when_every_lane_is_dead_the_list_comes_back_for_the_typed_offline
    lanes = [AGY, OPUS]
    Quota.note(AGY, AGY_REPLY)
    Quota.note(OPUS, CLAUDE_REPLY)
    assert_empty Selection.order(lanes)
    assert_nil Selection.first_live(lanes)
    # The refusal list is ranked, not the given order: a walk that must try
    # something anyway, or name why it cannot, walks the class ranks and not
    # the file order that let dead :free slugs burn a queue (2026-11-07).
    assert_equal Selection.ranked_order(lanes), Selection.order_or_all(lanes)
    assert_equal [OPUS, AGY], Selection.order_or_all(lanes), "subscription claude-cli ranks ahead of agy"
  end

  def test_the_always_online_tail_answers_when_every_remote_lane_is_dead
    models = Selection.catalogue
    models.map { |m| Quota.lane_of(m) }.uniq.reject { |lane| lane == "ollama" }.each { |lane| Quota.note("#{lane}:x", CLAUDE_REPLY) }

    live = Selection.order(models)
    refute_empty live
    assert Master::Io::LaneHealth.local_model?(live.first), "a local model leads: #{live}"
    assert(live.none? { |m| Selection.kind(m) == :remote }, "no remote model is left: #{live}")
    assert_match(/\Aonline: yes via ollama:/, Master::Io::LaneHealth.line(models, refuses: ->(m) { Quota.dead?(m) }))
  end

  def test_personas_spread_across_live_providers_and_never_to_free_while_a_lane_lives
    Quota.note(AGY, AGY_REPLY)
    candidates = [AGY, NEMOTRON, OPUS, SONNET, NANO, GROK, DEEPSEEK, LOCAL]
    names = %w[A B C D E F]

    lanes = Selection.spread(names, candidates)

    assert_equal [OPUS, GROK, OPUS, GROK, OPUS, GROK], lanes.values
    assert(lanes.values.none? { |m| Selection.kind(m) == :free }, "no free model while a live lane exists")
    refute_includes lanes.values, AGY
  end

  def test_one_live_provider_is_reused_and_free_is_the_last_resort
    assert_equal({ "A" => OPUS, "B" => OPUS }, Selection.spread(%w[A B], [OPUS, SONNET, NEMOTRON]))
    assert_equal({ "A" => NEMOTRON, "B" => NEMOTRON }, Selection.spread(%w[A B], [NEMOTRON, NANO]))
    assert_equal({ "A" => nil }, Selection.spread(%w[A], []))
  end

  # A counting agent with the real provider spellings: nothing is called that the
  # selection did not hand it, and the free nemotron lanes are never asked.
  class CountingAgent
    attr_reader :asked, :candidate_calls

    def initialize(models)
      @models = models
      @asked = []
      @candidate_calls = 0
    end

    def candidate_models(_message = nil, task_type: nil)
      @candidate_calls += 1
      @task = task_type
      @models
    end

    attr_reader :task

    def ask_once(_prompt, model: nil, **)
      @asked << model
      CouncilAnswer.json
    end

    def ask(_prompt, **)
      @asked << :routed
      CouncilAnswer.json
    end
  end

  Persona = Struct.new(:name, :role, :bias, :prompt, :veto_role, :emphasizes, keyword_init: true) do
    def veto? = !!veto_role
  end

  def test_the_council_reaches_the_selection_and_skips_dead_and_free_lanes
    Quota.note(AGY, AGY_REPLY)
    agent = CountingAgent.new([AGY, NEMOTRON, OPUS, GROK, NANO, LOCAL])
    personas = Array.new(4) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }
    delib = Master::Review::Council::Deliberation.new(personas:, agent:, judge_enabled: false)

    counting(:spread) do |calls|
      personas.each { |persona| delib.send(:ask_persona, persona:, code: "x = 1", context: nil) }
      refute_empty calls, "ask_persona never reached LaneSelection.spread"
    end

    assert_equal [OPUS, GROK, OPUS, GROK], agent.asked
    assert_equal :review, agent.task
    assert_equal 1, agent.candidate_calls, "the lane list is read once per council"
  end

  def test_a_critique_panel_reaches_the_selection
    Quota.note(AGY, AGY_REPLY)
    agent = CountingAgent.new([AGY, OPUS, NEMOTRON, GROK])
    critique = Master::Review::Council::Critique.new(mode: :general, agent:, files: [__FILE__])

    counting(:spread) do |calls|
      # The wiring under test is critique -> panel -> spread, not host
      # reachability: a box with no keys and no CLI would otherwise skip the
      # panel before it convenes. Reachability has its own tests.
      Master::Review::Council::Deliberation.stub(:reachable_for?, true) do
        critique.run
      end
      refute_empty calls, "Critique#run never reached LaneSelection.spread"
    end

    refute_empty agent.asked
    named = agent.asked.compact - [:routed]
    refute_empty named, "no persona was given a lane"
    assert(named.all? { |m| [OPUS, GROK].include?(m) }, "asked: #{agent.asked.tally}")
  end

  # A real router with its probes and telemetry replaced by pass-throughs, so the
  # chain it returns is what the selection made of the chain it was given.
  def router_over(chain, tier_rows)
    router = Master::CLI::Routing::ModelRouter.allocate
    router.instance_variable_set(:@rules, { "routes" => { "code_generation" => "default", "chitchat" => "free", "exploration" => "free" },
                                            "models" => { "default" => tier_rows.map { |id| { "id" => id } }, "free" => tier_rows.map { |id| { "id" => id } } } })
    passthrough = Object.new.tap do |o|
      o.define_singleton_method(:rank) { |ids, **| ids }
      o.define_singleton_method(:select) { |ids, **| ids.first }
    end
    router.instance_variable_set(:@compute_pool, passthrough)
    router.instance_variable_set(:@provider_health, passthrough)
    router.instance_variable_set(:@capability_map, Object.new.tap { |o| o.define_singleton_method(:best_model_for) { |_| nil } })
    router.define_singleton_method(:chain_for) { |_task| chain }
    router.define_singleton_method(:reachable?) { |_id| true }
    router.define_singleton_method(:recently_failed?) { |_id| false }
    router.define_singleton_method(:healthy) { |models| models }
    router.define_singleton_method(:prefer_floor) { |all, _fresh, **| all }
    router
  end

  def test_the_router_chain_and_preferred_pass_through_the_selection
    Quota.note(AGY, AGY_REPLY)
    chain = [NEMOTRON, AGY, NANO, OPUS, GROK]
    router = router_over(chain, [NEMOTRON, AGY, OPUS])

    counting(:order_or_all) do |calls|
      assert_equal [OPUS, GROK, NEMOTRON, NANO], router.fallback_chain(task_type: :code_generation)
      refute_empty calls, "fallback_chain never reached LaneSelection"
    end
    counting(:best_class) do |calls|
      assert_equal OPUS, router.preferred(task_type: :code_generation)
      refute_empty calls, "preferred never reached LaneSelection"
    end
  end

  def test_a_free_route_keeps_free_candidates_ahead_of_paid_fallbacks
    router = router_over([NEMOTRON, OPUS], [NEMOTRON, OPUS])
    assert_equal [NEMOTRON, OPUS], router.fallback_chain(task_type: :exploration)
    assert_equal NEMOTRON, router.preferred(task_type: :exploration)
  end

  def test_a_keyed_hosted_lane_never_precedes_a_keyless_lane_on_a_free_route
    keyless = "llm7:GLM-5.3-Flash"
    paid = "perplexity:sonar-pro"
    router = router_over([paid, keyless], [paid, keyless])
    router.define_singleton_method(:hosted_model?) { |id| id.start_with?("llm7:", "perplexity:") }
    router.define_singleton_method(:hosted_endpoint_for) do |id|
      id.start_with?("perplexity:") ? { key: "configured-key" } : { key: nil }
    end

    assert_equal [keyless, paid],
                 router.priority_fallback_order([paid, keyless], task_type: :exploration)
    assert_equal [paid, keyless],
                 router.priority_fallback_order([keyless, paid], task_type: :refactoring)
  end

  Config = Struct.new(:task_type, :model, :reasoning_mode, keyword_init: true)

  def test_agent_model_selector_preserves_the_task_specific_free_route
    cohere_free = "cohere/north-mini-code:free"
    router = router_over([cohere_free, GROK], [cohere_free, GROK])
    selector = Object.new.extend(Master::Review::Agent::ModelSelector)
    selector.instance_variable_set(:@model_router, router)
    selector.instance_variable_set(:@config, Config.new(task_type: "code_generation", model: GROK))
    selector.instance_variable_set(:@homeostat, nil)

    assert_equal [GROK, cohere_free],
                 selector.send(:routed_chain, nil, task_type: :code_generation)
    assert_equal [cohere_free, GROK],
                 selector.send(:routed_chain, nil, task_type: :exploration)
  end

  # The fix loop asks through the real Agent: ask -> routed chain -> router ->
  # LaneSelection. The dispatcher is a counting stub that records which model the
  # request was addressed to, in the real provider spellings.
  def test_the_repair_loop_request_reaches_the_selection_and_lands_on_the_first_live_lane
    Quota.note(AGY, AGY_REPLY)
    router = router_over([NEMOTRON, AGY, OPUS, GROK, NANO], [NEMOTRON, AGY, OPUS])
    sent = []
    dispatcher = Object.new
    dispatcher.define_singleton_method(:send_with_cache) { |model, *_a, **_k| sent << model; Master::Result.ok("fixed") }
    agent = Master::Review::Agent.allocate
    agent.instance_variable_set(:@model_router, router)
    agent.instance_variable_set(:@dispatcher, dispatcher)
    agent.instance_variable_set(:@config, Config.new(task_type: "code_generation", model: OPUS))
    agent.instance_variable_set(:@bus, nil)
    law = Struct.new(:id, :severity).new("TEST_RULE", :warning)
    loop = Master::Fix::RepairLoop.new(law:, agent:, scanner: Object.new, root: Master::ROOT, bus: nil)

    counting(:order_or_all) do |calls|
      assert_equal "fixed", loop.send(:ask_agent, "repair this")
      refute_empty calls, "the repair loop's ask never reached LaneSelection"
    end

    assert_equal [OPUS], sent, "the first live lane of the tier, not the dead agy and not a free nemotron"
  end

  def test_a_recent_provider_failure_changes_the_next_router_selection
    health = Master::CLI::Routing::ProviderHealth.new(
      path: File.join(@dir, "provider-health.ndjson"),
      now: -> { Time.at(NOON).utc },
    )
    health.record(model: OPUS, status: :provider_error, at: Time.at(NOON).utc)

    router = router_over([OPUS, GROK], [OPUS, GROK])
    router.instance_variable_set(:@provider_health, health)
    router.define_singleton_method(:recently_failed?) do |model_id|
      health.recently_failed?(model_id, max_age_s: 900)
    end

    assert_equal [GROK], router.fallback_chain(task_type: :code_generation)
  end

  # A launch script whose PATH leaves out ~/.local/bin, where the installer puts claude, still finds it there.
  def test_claude_outside_path_is_found_in_the_user_bin
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "claude"), "#!/bin/sh\n")
      File.chmod(0o755, File.join(bin, "claude"))
      found, missing = with_path("/usr/bin:/bin") do
        [Master::Io::Exec.cli_binary("claude", user_bins: [bin]), Master::Io::Exec.cli_binary("claude", user_bins: [])]
      end

      assert_equal [File.join(bin, "claude"), nil], [found, missing]
    end
  end

  def with_path(path)
    previous = ENV.fetch("PATH")
    ENV["PATH"] = path
    yield
  ensure
    ENV["PATH"] = previous
  end
  def test_routing_failure_falls_back_to_the_model_catalogue
    config = Struct.new(:model, :task_type).new(GROK, :general)
    router = Object.new
    router.define_singleton_method(:classify_intent) { |*| raise IOError, "router unavailable" }
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |name, **payload| events << [name, payload] }
    selector = Object.new.extend(Master::Review::Agent::ModelSelector)
    selector.instance_variable_set(:@config, config)
    selector.instance_variable_set(:@model_router, router)
    selector.instance_variable_set(:@bus, bus)

    chain = selector.send(:routed_chain, "write a parser", task_type: :general)

    assert_operator chain.length, :>, 1, "a route error must retain independent alternatives"
    assert_equal GROK, chain.last, "the configured model remains the final fallback"
    assert_equal chain.uniq, chain
    assert(events.any? { |name, _| name == "llm:route_error" })
    assert(events.any? { |name, payload| name == "llm:route_fallback" && payload[:source] == "models_catalogue" })
  end

  def test_missing_router_uses_the_independent_model_catalogue
    config = Struct.new(:model, :task_type).new(GROK, :general)
    selector = Object.new.extend(Master::Review::Agent::ModelSelector)
    selector.instance_variable_set(:@config, config)
    selector.instance_variable_set(:@model_router, nil)

    chain = selector.send(:routed_chain, "write a parser", task_type: :general)

    assert_operator chain.length, :>, 1, "the router is optional during recovery"
    assert_equal GROK, chain.last
  end

  # The pass-0 child's bus events never reach the parent's pulse, so the free
  # floor counts its own dead outcomes with the dispatcher's funnel feeding it.
  # The keyless gateways' slugs are the free floor the walk rides; the
  # kilo:openrouter/free pool walked 66 dead attempts without ever counting
  # as a free-class death because kind() called it remote.
  def test_the_verified_keyless_gateway_slugs_are_free_class
    ids = %w[kilo:openrouter/free kilo:reflection/beam-free ovh:gpt-oss-120b]
    with_hosted_models(ids, keyless: true) do
      config = Selection.config
      %w[kilo:openrouter/free kilo:reflection/beam-free].each do |id|
        assert_equal :free, Selection.kind(id, cfg: config),
                     "#{id} answers without a key and is the floor"
      end
      assert_equal :free, Selection.kind("ovh:gpt-oss-120b", cfg: config),
                   "the allow-listed keyless OVH slug is free-class keylessly"
      refute_equal :free, Selection.kind("kilo:dots-studio/paid-slug", cfg: config),
                   "a slug the gateway does not offer keylessly is not free-class"
    end
  end

  # With the provider's own key set, the same gateway answers its paid slugs;
  # the keyless classification holds only for keyless use.
  def test_a_set_provider_key_moves_the_gateway_off_the_free_class
    previous_key = ENV["KILO_API_KEY"]
    ENV["KILO_API_KEY"] = "operator-set-operator-key-with-at-least-20-chars"
    with_hosted_models(["kilo:openrouter/free"]) do
      config = Selection.config
      assert_equal :remote, Selection.kind("kilo:openrouter/free", cfg: config),
                   "with the gateway's key, the slug may be a paid route"
    end
  ensure
    previous_key.nil? ? ENV.delete("KILO_API_KEY") : ENV["KILO_API_KEY"] = previous_key
  end

  def test_three_dead_free_class_outcomes_suspend_the_floor_from_inside_the_process
    notices = []
    Selection.define_singleton_method(:announce_free_floor_suspension) do
      notices << "free floor suspended"
    ensure
      @floor_notice = nil
    end
    Selection.watch_free_class!
    refute_predicate Selection, :free_floor_suspended?

    3.times { Selection.note_provider_outcome(NEMOTRON, :failure, alive: ALL) }

    refute_predicate Selection, :free_floor_suspended?,
                     "three free failures cannot promote a paid lane that has only been configured"
    assert_empty notices
    Selection.note_provider_outcome(OPUS, :success, alive: ALL)

    assert_predicate Selection, :free_floor_suspended?,
                     "a successful non-free completion is the evidence needed to suspend the floor"
    assert_equal ["free floor suspended"], notices, "the suspension prints exactly one line"
    assert_nil Selection.instance_variable_get(:@floor_notice),
                 "the notice is consumed by the announce that printed it"
  ensure
    Selection.watch_free_class!(false)
  end

  def test_one_free_class_success_lifts_the_dead_count_but_non_free_deaths_never_count
    notices = []
    Selection.define_singleton_method(:announce_free_floor_suspension) do
      notices << "free floor suspended"
    ensure
      @floor_notice = nil
    end
    Selection.watch_free_class!

    # Paid deaths are the wrong room's grief; the free floor ignores them.
    3.times { Selection.note_provider_outcome(OPUS, :failure, alive: ALL) }
    refute_predicate Selection, :free_floor_suspended?,
                     "a dead paid lane is not a dead floor"

    # Two free deaths, then the floor genuinely answering, then one more.
    2.times { Selection.note_provider_outcome(NEMOTRON, :failure, alive: ALL) }
    Selection.note_provider_outcome(NEMOTRON, :success, alive: ALL)
    Selection.note_provider_outcome(NEMOTRON, :failure, alive: ALL)
    refute_predicate Selection, :free_floor_suspended?,
                     "a working free lane stands the floor back up"
    assert_empty notices
  ensure
    Selection.watch_free_class!(false)
  end

  def test_a_suspended_floor_does_not_suspend_twice_and_the_turn_resets_it
    Selection.define_singleton_method(:announce_free_floor_suspension) do
      @announced = true
    ensure
      @floor_notice = nil
    end
    Selection.watch_free_class!
    # Suspension is justified only after a non-free lane has actually answered
    # and remains usable. Model that external health evidence deterministically.
    Selection.stub(:live_savior, ->(**) { OPUS }) do
      Master::Io::LaneState.stub(:usable?, ->(id, **_kwargs) { id == OPUS }) do
        Selection.note_provider_outcome(OPUS, :success, alive: ALL)
        3.times { Selection.note_provider_outcome(NANO, :timeout, alive: ALL) }
        assert_predicate Selection, :free_floor_suspended?
        assert_nil Selection.suspend_free_floor!(OPUS),
                   "the guard refuses a second suspension; the first verdict holds"

        # A new /fix turn re-arms the watch and clears the suspension with the count.
        Selection.watch_free_class!
        refute_predicate Selection, :free_floor_suspended?,
                         "the next turn is allowed to try the floor again"
      end
    end
  ensure
    Selection.watch_free_class!(false)
  end

  # The pass-0 walk of 2026-11-07 burned its queue on dead :free slugs while a
  # live non-free lane answered and the floor was already suspended: the order
  # the walk tried came from the file, not from the class ranks. Suspension
  # must demote the floor in the same sort that ranks free lanes last.
  def test_a_suspended_floor_rides_behind_every_answering_class
    mixed = [NEMOTRON, LOCAL, DEEPSEEK, GROK]
    assert_equal [GROK, DEEPSEEK, LOCAL, NEMOTRON], Selection.order(mixed), "free stays last while the floor stands"

    Selection.watch_free_class!
    Selection.note_provider_outcome(OPUS, :success, alive: ALL)
    Selection.suspend_free_floor!(OPUS)
    assert_equal [GROK, DEEPSEEK, LOCAL, NEMOTRON], Selection.order(mixed),
                 "free and local stay in the list, never-modelless keeps them, but every remote goes first"
    assert_equal [LOCAL, NEMOTRON], Selection.order([NEMOTRON, LOCAL]),
                 "with no remote left, the floor keeps its own order"
    assert_equal [NEMOTRON, LOCAL, DEEPSEEK, GROK], Selection.order(mixed, free_last: false),
                 "a free-on-purpose route keeps its given order, never demoted"
  ensure
    Selection.watch_free_class!(false)
  end

  def test_the_all_dead_fallback_returns_the_ranked_order_not_the_given_order
    mixed = [NEMOTRON, LOCAL, DEEPSEEK, GROK]
    Selection.stub(:order, ->(_models, **_kw) { [] }) do
      assert_equal [GROK, DEEPSEEK, LOCAL, NEMOTRON], Selection.order_or_all(mixed),
                   "the refusal order goes through the ranking, so a walk that tries anyway is ranked"
    end
  end

  def test_a_suspended_floor_is_ranked_last_even_in_the_all_dead_fallback
    mixed = [NEMOTRON, DEEPSEEK, GROK]
    Selection.watch_free_class!
    Selection.note_provider_outcome(OPUS, :success, alive: ALL)
    Selection.suspend_free_floor!(OPUS)
    Selection.stub(:order, ->(_models, **_kw) { [] }) do
      assert_equal [GROK, DEEPSEEK, NEMOTRON], Selection.order_or_all(mixed),
                   "the suspended free slug cannot jump a dead remote just because it was listed first"
    end
  ensure
    Selection.watch_free_class!(false)
  end

end
