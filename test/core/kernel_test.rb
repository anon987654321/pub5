# frozen_string_literal: true

require_relative "../test_helper"

class KnobsTest < Minitest::Test
  include TestHelper

  def test_an_undeclared_env_name_is_refused
    error = assert_raises(Core::Refusal) { knobs("HOME" => "/x").fetch("HOME") }
    assert_equal :env, error.verb
    assert_match(/not declared/, error.message)
  end

  def test_declared_knobs_cast_and_default
    k = knobs("PUB5_HTTP_TIMEOUT" => "7", "PUB5_OFFLINE" => "yes")
    assert_equal 7, k.fetch("PUB5_HTTP_TIMEOUT")
    assert_equal true, k.fetch("PUB5_OFFLINE")
    assert_equal 120, k.fetch("PUB5_EXEC_TIMEOUT")
    assert_equal File.join(Core::ROOT, "log/ledger.jsonl"), k.fetch("PUB5_LEDGER")
    assert_raises(Core::Refusal) { knobs("PUB5_HTTP_TIMEOUT" => "soon").fetch("PUB5_HTTP_TIMEOUT") }
  end

  def test_the_registry_stays_within_the_budget
    declared = Core::Registry.load(:knobs).fetch("knobs")
    assert_operator declared.size, :<=, Core::Knobs::LIMIT
    too_many = (1..41).to_h { |i| ["K#{i}", { "type" => "string", "default" => nil, "purpose" => "x" }] }
    assert_raises(Core::Refusal) { Core::Knobs.new(too_many, env: {}) }
  end

  def test_every_env_name_a_registry_mentions_is_a_declared_knob
    declared = Core::Registry.load(:knobs).fetch("knobs").keys
    models = Core::Registry.load(:models)
    named = models.fetch("providers").values.flat_map { |p| p["env"] } +
            models.fetch("openai_compatible").values.flat_map { |p| p["key_env"] } +
            models.dig("openrouter", "keys_env") + [models.dig("ferrum_web_chat", "enabled_when_env")] +
            models.dig("media_lanes", "providers").values.flat_map { |p| p["env"] || [] }
    assert_empty named.uniq - declared
  end
end

class RegistryTest < Minitest::Test
  include TestHelper

  def test_every_registry_validates_against_its_schema
    names = Core::Registry.names
    assert_empty %w[apps knobs models paths writers] - names
    names.each { |name| Core::Registry.load(name) }
  end

  def test_a_registry_without_a_schema_or_off_schema_is_refused
    sandbox do |root|
      put(root, "schemas/one.yml", "type: object\nrequired: [a]\n")
      put(root, "one.yml", "b: 1\n")
      put(root, "two.yml", "a: 1\n")
      assert_match(/missing a/, assert_raises(Core::Refusal) { Core::Registry.load(:one, dir: root) }.message)
      assert_match(/no schema/, assert_raises(Core::Refusal) { Core::Registry.load(:two, dir: root) }.message)
    end
  end

  def test_loaded_registries_are_frozen
    assert_predicate Core::Registry.load(:apps).dig("apps", "brgen"), :frozen?
  end

  def test_ported_facts_survive
    apps = Core::Registry.load(:apps)
    assert_equal 38_182, apps.dig("apps", "brgen", "port")
    assert_equal "amberapp.art", apps.dig("apps", "amber", "domain")
    assert_includes Core::Registry.load(:models).fetch("lanes").fetch("dead"), "codex-cli"
  end

  def test_inbox_writers_cannot_reach_core_laws_or_registry
    Core::Registry.load(:writers).fetch("writers").each do |name, w|
      next if w["trust"] == "main"

      assert_equal ["inbox/#{name}"], w["branches"]
      assert_empty w["trees"] & %w[all core laws registry bin], name
    end
  end
end

class AtomicTest < Minitest::Test
  include TestHelper

  def test_replaces_bytes_and_keeps_mode
    sandbox do |root|
      path = File.join(root, "a/b.txt")
      Core::Atomic.write(path, "one", mode: 0o600)
      Core::Atomic.write(path, "two")
      assert_equal "two", File.read(path)
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal ["b.txt"], Dir.children(File.dirname(path))
    end
  end

  def test_refuses_symlinks_and_hard_links
    sandbox do |root|
      put(root, "real.txt", "r")
      File.symlink(File.join(root, "real.txt"), File.join(root, "link.txt"))
      File.link(File.join(root, "real.txt"), File.join(root, "hard.txt"))
      assert_raises(Core::Refusal) { Core::Atomic.write(File.join(root, "link.txt"), "x") }
      assert_raises(Core::Refusal) { Core::Atomic.write(File.join(root, "hard.txt"), "x") }
      assert_equal "r", File.read(File.join(root, "real.txt"))
    end
  end
end

class LedgerTest < Minitest::Test
  include TestHelper

  def test_appends_and_never_rewrites
    sandbox do |root|
      ledger = Core::Ledger.new(File.join(root, "l.jsonl"))
      ledger.append(:llm, tokens_in: 10, tokens_out: 5, cost_usd: 0.25)
      first = File.read(ledger.path)
      ledger.append(:llm, tokens_in: 1, tokens_out: 1, cost_usd: nil)
      assert File.read(ledger.path).start_with?(first)
      assert_equal({ "calls" => 2, "tokens_in" => 11, "tokens_out" => 6, "cost_usd" => 0.25, "unpriced_calls" => 1 }, ledger.spend)
    end
  end
end

class LLMTest < Minitest::Test
  include TestHelper

  Fake = Struct.new(:status, :body, :seen) do
    def request(method, url, **options)
      self.seen = [method, url, options]
      Core::HTTP::Reply.new(status:, headers: {}, body:)
    end
  end

  MODELS = {
    "providers" => {
      "anthropic" => { "env" => ["ANTHROPIC_API_KEY"], "protocol" => "anthropic", "base" => "https://api.anthropic.com/v1" },
      "openrouter" => { "env" => ["OPENROUTER_API_KEY"], "protocol" => "openai", "base" => "https://openrouter.ai/api/v1" },
      "agy" => { "env" => ["AGY_BIN"] }
    },
    "prices" => { "m" => { "prompt_usd_per_m" => 3.0, "completion_usd_per_m" => 15.0 } }
  }.freeze

  def client(fake, env, ledger)
    Core::LLM.new(models: MODELS, knobs: knobs(env), ledger:, transport: fake)
  end

  def test_records_tokens_and_cost_in_the_ledger
    sandbox do |root|
      ledger = Core::Ledger.new(File.join(root, "l.jsonl"))
      fake = Fake.new(200, '{"choices":[{"message":{"content":"ok"}}],"usage":{"prompt_tokens":1000,"completion_tokens":100}}')
      answer = client(fake, { "OPENROUTER_API_KEY" => "k" }, ledger).complete(provider: "openrouter", model: "m", messages: [])
      assert_equal "ok", answer.text
      assert_in_delta 0.0045, answer.cost_usd
      assert_equal "https://openrouter.ai/api/v1/chat/completions", fake.seen[1]
      assert_equal 1000, ledger.entries.last["tokens_in"]
    end
  end

  def test_unpriced_models_are_unmeasured_not_free
    sandbox do |root|
      ledger = Core::Ledger.new(File.join(root, "l.jsonl"))
      fake = Fake.new(200, '{"content":[{"text":"a"}],"usage":{"input_tokens":2,"output_tokens":3}}')
      assert_nil client(fake, { "ANTHROPIC_API_KEY" => "k" }, ledger).complete(provider: "anthropic", model: "other", messages: []).cost_usd
      assert_equal 1, ledger.spend["unpriced_calls"]
    end
  end

  def test_refusals_before_any_request
    sandbox do |root|
      ledger = Core::Ledger.new(File.join(root, "l.jsonl"))
      fake = Fake.new(200, "{}")
      call = ->(env, provider = "anthropic") { client(fake, env, ledger).complete(provider:, model: "m", messages: []) }
      assert_match(/no key/, assert_raises(Core::Refusal) { call.call({}) }.message)
      assert_match(/OFFLINE/, assert_raises(Core::Refusal) { call.call({ "ANTHROPIC_API_KEY" => "k", "PUB5_OFFLINE" => "1" }) }.message)
      assert_match(/protocol/, assert_raises(Core::Refusal) { call.call({}, "agy") }.message)
      ledger.append(:llm, tokens_in: 0, tokens_out: 0, cost_usd: 2.0)
      assert_match(/budget/, assert_raises(Core::Refusal) { call.call({ "ANTHROPIC_API_KEY" => "k", "PUB5_RUN_BUDGET_USD" => "1.5" }) }.message)
      assert_nil fake.seen
    end
  end

  def test_http_errors_are_recorded_and_refused
    sandbox do |root|
      ledger = Core::Ledger.new(File.join(root, "l.jsonl"))
      assert_raises(Core::Refusal) do
        client(Fake.new(429, "{}"), { "ANTHROPIC_API_KEY" => "k" }, ledger).complete(provider: "anthropic", model: "m", messages: [])
      end
      assert_equal 429, ledger.entries.last["status"]
    end
  end
end

class ParseGateTest < Minitest::Test
  include TestHelper

  CASES = {
    "a.rb" => ["def x = 1\n", "def x(\n"],
    "a.yml" => ["a: [1, 2]\n", "a: [1, 2\n"],
    "a.json" => ['{"a": 1}', '{"a": }'],
    "a.html.erb" => ["<%= form_with do |f| %>\n<%= f.text_field :x %>\n<% end %>\n", "<% if x %>\n"]
  }.freeze

  def test_good_files_pass_and_broken_files_are_named
    sandbox do |root|
      CASES.each do |name, (good, bad)|
        put(root, "good/#{name}", good)
        put(root, "bad/#{name}", bad)
      end
      problems = Core::ParseGate.check(CASES.keys.flat_map { |n| ["good/#{n}", "bad/#{n}"] }, root:)
      assert_equal CASES.keys.map { |n| "bad/#{n}" }.sort, problems.map(&:first).sort
    end
  end

  def test_ruby_scripts_without_an_extension_are_ruby
    sandbox do |root|
      put(root, "bin/tool", "#!/usr/bin/env ruby\nputs(\n")
      assert_equal ["bin/tool"], Core::ParseGate.check(["bin/tool"], root:).map(&:first)
    end
  end
end
