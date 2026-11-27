# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeBenchmark < Minitest::Test
  def test_measure_is_deterministic_for_hash_key_order
    first = Master::Runtime::Benchmark.measure(label: "hash") { { b: 2, a: 1 } }
    second = Master::Runtime::Benchmark.measure(label: "hash") { { a: 1, b: 2 } }

    assert_equal first[:output_digest], second[:output_digest]
  end

  def test_compare_reports_output_change_and_regression
    before = { output_digest: "abc", wall_ms: 10.0 }
    after = { output_digest: "def", wall_ms: 12.0 }
    comparison = Master::Runtime::Benchmark.compare(before, after)

    refute comparison[:output_equal]
    assert comparison[:regression]
    assert_equal 1.2, comparison[:ratio]
  end
end

require_relative "test_helper"

class TestRuntimeBox < Minitest::Test
  def test_snapshot_has_stable_shape
    snapshot = Master::Runtime::Box.snapshot

    %i[present enabled available startup_required startup_env current].each do |key|
      assert snapshot.key?(key)
    end
  end

  def test_box_capability_is_truthful
    if defined?(::Ruby::Box) && ::Ruby::Box.respond_to?(:enabled?)
      assert_equal ::Ruby::Box.enabled?, Master::Runtime::Box.enabled?
    else
      refute Master::Runtime::Box.enabled?
    end
  end

  def test_box_requires_startup_enablement
    skip "Ruby::Box is enabled, so there is no unavailable path to exercise" if Master::Runtime::Box.available?

    error = assert_raises(Master::Runtime::Box::Unavailable) do
      Master::Runtime::Box.new_box
    end
    assert_match(/Ruby::Box/, error.message)
  end

  def test_box_evaluation_preserves_explicit_box_requirement
    skip "Ruby::Box is enabled, so there is no unavailable path to exercise" if Master::Runtime::Box.available?

    assert_raises(Master::Runtime::Box::Unavailable) do
      Master::Runtime::Box.evaluate("1 + 1")
    end
  end

  def test_runtime_source_exposes_isolation_operations
    source = File.read(File.expand_path("../lib/runtime/box.rb", __dir__))

    assert_includes source, "::Ruby::Box.new"
    assert_includes source, "box.eval"
    assert_includes source, "box.load"
    assert_includes source, "RUBY_BOX"
  end
end

require_relative "test_helper"
require_relative "../lib/configuration_guard"
require_relative "../lib/ground/boot_checks"

class TestRuntimeCatalogueValidation < Minitest::Test
  Guard = Master::ConfigurationGuard
  BootChecks = Master::Ground::BootChecks

  def catalogue_path(name)
    File.join(Master::ROOT, "data", name)
  end

  def validated_file(name)
    path = catalogue_path(name)
    Guard.validate(path:, content: File.read(path, encoding: "UTF-8"))
  end

  def test_live_provider_catalogue_satisfies_schema
    assert_nil validated_file("providers.yml")
  end

  def test_live_model_catalogue_satisfies_schema_and_references
    assert_nil validated_file("models.yml")
  end

  def test_paid_tail_budget_matches_enabled_state
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    paid = data.fetch("paid_tail")
    [[false, 0, true], [false, -1, false], [true, 0, false], [true, 1, true], [false, Float::INFINITY, false]].each do |enabled, cap, valid|
      paid.merge!("enabled" => enabled, "run_cap_usd" => cap)
      error = Guard.validate(path:, content: YAML.dump(data))
      if valid
        assert_nil error
      else
        assert_match(/paid_tail.run_cap_usd/, error)
      end
    end
  end

  def test_the_declared_nsfw_tier_may_be_empty
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("models")["nsfw"] = []

    assert_nil Guard.validate(path:, content: YAML.dump(data))
  end

  def test_model_definition_identifiers_may_contain_underscores
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    example = data.fetch("model_defs").values.first
    data.fetch("model_defs")["underscore_probe"] = example.merge("id" => "model_identifier_with_underscores")

    assert_nil Guard.validate(path:, content: YAML.dump(data))
  end

  def test_other_model_tiers_must_not_be_empty
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("models")["fast"] = []

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/models.fast must be a non-empty list/, error)
  end

  def test_keyless_endpoint_requires_a_selection_rule
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("openai_compatible").fetch("llm7").fetch("keyless")["tier"] = nil

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/models.yml openai_compatible.llm7.keyless.tier must be non-empty text unless allow or isFree selects/, error)
  end

  def test_keyless_endpoint_rejects_non_text_tier_without_raising
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("openai_compatible").fetch("llm7").fetch("keyless")["tier"] = 7

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/models.yml openai_compatible.llm7.keyless.tier must be non-empty text/, error)
  end

  def test_replicate_chat_budget_requires_a_price_for_every_automatic_model
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("replicate_chat_budget").fetch("prices_usd_per_million").delete("openai/gpt-5.2")

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/replicate_chat_budget missing prices for openai\/gpt-5\.2/, error)
  end

  def test_replicate_chat_budget_rejects_nonpositive_model_prices
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("replicate_chat_budget").fetch("prices_usd_per_million")
      .fetch("openai/gpt-5.2")["output"] = 0

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/replicate_chat_budget\.prices_usd_per_million\.openai\/gpt-5\.2\.output must be positive/, error)
  end

  def test_media_lanes_must_reference_declared_media_providers
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("media_lanes").fetch("image").first["provider"] = "missing_provider"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/models.yml media_lanes.image\[0\].provider must name a declared media provider/, error)
  end

  def test_validator_helpers_are_private_without_hiding_public_helpers
    refute Master::ModelCatalogueGuard.respond_to?(:validate_top_level)
    assert Master::ModelCatalogueGuard.respond_to?(:validate_scores)
    refute Master::ModelCatalogueSectionsGuard.respond_to?(:validate_cli_lane)
    assert Master::ModelCatalogueSectionsGuard.respond_to?(:strict_fields)
  end

  def test_ollama_enabled_must_be_a_boolean
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("ollama")["enabled"] = "false"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/models.yml ollama.enabled must be boolean/, error)
  end

  def test_provider_registry_rejects_a_non_array_environment_list
    path = catalogue_path("providers.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("openrouter")["env"] = "OPENROUTER_API_KEY"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/provider openrouter\.env must be a unique list/, error)
  end

  def test_unknown_provider_fields_are_rejected
    path = catalogue_path("providers.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("openrouter")["api_key_environemnt"] = "OPENROUTER_API_KEY"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/provider openrouter has unknown field\(s\): api_key_environemnt/, error)
  end

  def test_model_routes_must_reference_declared_tiers
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("routes")["code_generation"] = "catalogue_typo"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/models\.yml route code_generation must reference a declared model tier/, error)
  end

  def test_unknown_nested_model_policy_fields_are_rejected
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("routing")["provder"] = "agy"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/models\.yml routing has unknown field\(s\): provder/, error)
  end

  def test_media_lane_promotion_must_have_a_valid_date_and_lower_price
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    lane = data.fetch("media_lanes").fetch("video").find { |row| row["model"] == "minimax/h3-lite" }
    lane.fetch("promotion")["until"] = "2026-13-40"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/media_lanes.video\[0\].promotion.until must be a YYYY-MM-DD date/, error)
  end

  def test_boot_checks_apply_model_reference_validation_before_startup
    Dir.mktmpdir("master-model-catalogue-boot") do |tmp|
      root = File.join(tmp, "MASTER")
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)

      providers_path = File.join(data_dir, "providers.yml")
      models_path = File.join(data_dir, "models.yml")
      FileUtils.cp(catalogue_path("providers.yml"), providers_path)
      data = YAML.safe_load_file(catalogue_path("models.yml"), aliases: true)
      data.fetch("routes")["code_generation"] = "not_a_tier"
      File.write(models_path, YAML.dump(data))

      result = BootChecks.send(:check_models_yaml, root)

      refute result.ok
      assert_equal :fatal, result.severity
      assert_match(/models\.yml route code_generation must reference a declared model tier/, result.message)
    end
  end

  def test_model_scores_must_stay_in_the_closed_interval
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("model_defs").fetch("agy_auto").fetch("score")["quality"] = 1.5

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/model_defs\.agy_auto\.score\.quality must be between 0 and 1/, error)
  end

  def test_boot_checks_reject_invalid_dynamic_tool_catalogue
    Dir.mktmpdir("master-dynamic-tool-boot") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      path = File.join(data_dir, "tools.dynamic.yml")
      File.write(path, YAML.dump("name" => "broken_tool", "url" => "https://example.com"))

      result = BootChecks.send(:check_dynamic_tools_yaml, root)

      refute result.ok
      assert_equal :fatal, result.severity
      assert_match(/must be a YAML list/, result.message)
    end
  end

  def test_canonical_boot_validates_token_catalogue
    result = BootChecks.send(:check_tokens_yaml, Master::ROOT)

    assert result.ok, result.message
    assert_match(/schema and references valid/, result.message)
  end

  def test_canonical_boot_validates_provider_catalogue
    result = BootChecks.send(:check_providers_yaml, Master::ROOT)

    assert result.ok, result.message
    assert_match(/schema and references valid/, result.message)
  end

  def test_canonical_boot_validates_model_catalogue
    result = BootChecks.send(:check_models_yaml, Master::ROOT)

    assert result.ok, result.message
    assert_match(/schema and references valid/, result.message)
  end
end

require_relative "test_helper"

module Master
  class RuntimeComputeTestStage
    def initialize(multiplier)
      @multiplier = multiplier
    end

    def ractor_safe? = true

    def ractor_payload(ctx)
      { "message" => ctx[:user_message], "multiplier" => @multiplier }
    end

    def self.ractor_call(payload)
      { "ractor_#{payload.fetch("message")}_#{payload.fetch("multiplier")}" => payload.fetch("multiplier") }
    end
  end
end

class TestRuntimeCompute < Minitest::Test
  def test_serial_backend_preserves_order
    result = Master::Runtime::Compute.map([1, 2, 3], backend: :serial) { |value, index| value + index }

    assert_equal [1, 3, 5], result
  end

  def test_thread_backend_preserves_order
    result = Master::Runtime::Compute.map((0...16).to_a, backend: :thread) { |value, _index| value * 2 }

    assert_equal (0...16).map { |value| value * 2 }, result
  end

  def test_thread_backend_cleans_up_workers_when_startup_fails_partway
    original_new = Thread.method(:new)
    active = []
    started = Queue.new
    calls = 0

    Thread.stub(:new, lambda { |*args, **kwargs, &block|
      calls += 1
      raise ThreadError, "thread limit reached" if calls == 2

      original_new.call(*args, **kwargs) do
        active << Thread.current
        started << true
        block.call
      end.tap { started.pop }
    }) do
      error = assert_raises(ThreadError) do
        Master::Runtime::Compute.send(:thread_map, [1, 2], workers: 2, timeout: 1) do
          sleep 30
        end
      end
      assert_equal "thread limit reached", error.message
    end

    assert_equal 2, calls
    assert_equal 1, active.size
    refute active.first.alive?, "a worker created before startup failed must be stopped and joined"
  end

  def test_auto_selects_ractor_for_an_explicit_invoke_protocol
    skip "Ractors unavailable" unless Master::Runtime::Compute.ractor_available?

    jobs = 4.times.map do |value|
      ["Master::RuntimeComputeTestStage", "ractor_call", { "message" => value.to_s, "multiplier" => value + 1 }]
    end

    result = Master::Runtime::Compute.map(jobs, backend: :auto, operation: :invoke)

    assert_equal 4, result.size
    assert_equal({ "ractor_3_4" => 4 }, result[3])
    refute jobs.any? { |job| job.frozen? }, "Ractor preparation must not freeze caller-owned jobs"
  end

  def test_parallel_group_uses_ractors_for_ractor_safe_stages
    skip "Ractors unavailable" unless Master::Runtime::Compute.ractor_available?

    group = Master::CLI::Pipeline::ParallelGroup.new(
      Master::RuntimeComputeTestStage.new(2),
      Master::RuntimeComputeTestStage.new(3),
    )

    result = group.call(user_message: "hello")

    assert result.ok?, result.inspect
    assert_equal(
      { user_message: "hello", "ractor_hello_2" => 2, "ractor_hello_3" => 3 },
      result.value!,
    )
  end

  def test_ruby4_transport_uses_ractor_ports_when_available
    source = File.read(File.expand_path("../lib/runtime/compute.rb", __dir__))

    assert_includes source, "Ractor::Port"
    assert_includes source, "result_port.receive"
    assert_includes source, "respond_to?(:join)"
    assert_includes source, "ractor_port_available?"
  end

  def test_ractor_port_capability_is_feature_detected
    expected = defined?(Ractor::Port) && Ractor::Port.respond_to?(:new)
    assert_equal expected, Master::Runtime::Compute.ractor_port_available?
  end

  def test_parallel_group_can_force_the_thread_backend
    group = Master::CLI::Pipeline::ParallelGroup.new(
      Master::RuntimeComputeTestStage.new(2),
      Master::RuntimeComputeTestStage.new(3),
      backend: :thread,
    )

    result = group.call(user_message: "hello")

    refute result.ok?, "Ractor-only stages should not silently execute as Thread stages"
    assert_match(/undefined method|ractor|call/, result.message)
  end
end

require_relative "test_helper"

class TestRuntimeJit < Minitest::Test
  def test_mode_defaults_to_auto
    ENV.delete("MASTER_JIT")
    assert_equal "auto", Master::Runtime::Jit.mode
  end

  def test_invalid_mode_falls_back_to_auto
    previous = ENV["MASTER_JIT"]
    ENV["MASTER_JIT"] = "banana"
    assert_equal "auto", Master::Runtime::Jit.mode
  ensure
    previous ? ENV["MASTER_JIT"] = previous : ENV.delete("MASTER_JIT")
  end

  def test_off_does_not_enable
    Master::Runtime::Jit.stub(:available?, true) do
      Master::Runtime::Jit.stub(:enabled?, false) do
        ENV["MASTER_JIT"] = "off"
        refute Master::Runtime::Jit.apply!
      end
    end
  ensure
    ENV.delete("MASTER_JIT")
  end

  def test_zjit_is_an_explicit_opt_in_mode
    assert_includes Master::Runtime::Jit::MODES, "zjit"
    Master::Runtime::Jit.stub(:enable_zjit!, ->(reason:) { reason == "forced" }) do
      ENV["MASTER_JIT"] = "zjit"
      assert Master::Runtime::Jit.apply!
    end
  ensure
    ENV.delete("MASTER_JIT")
  end

  def test_zjit_is_not_auto_selected
    Master::Runtime::Jit.stub(:auto_allowed?, true) do
      Master::Runtime::Jit.stub(:enable_yjit!, ->(reason:) { reason == "auto" }) do
        ENV.delete("MASTER_JIT")
        assert Master::Runtime::Jit.apply!
      end
    end
  ensure
    ENV.delete("MASTER_JIT")
  end

  def test_snapshot_has_stable_shape
    snapshot = Master::Runtime::Jit.snapshot
    %i[mode available enabled constrained yjit_available yjit_enabled zjit_available zjit_enabled stats].each do |key|
      assert snapshot.key?(key)
    end
  end
end

require_relative "test_helper"

class TestRuntimeMode < Minitest::Test
  def test_summary_includes_safe_and_visitor_defaults
    saved = %w[MASTER_SAFE_MODE MASTER_WEB].to_h { |key| [key, ENV.fetch(key, nil)] }
    ENV["MASTER_SAFE_MODE"] = "1"
    ENV["MASTER_WEB"] = "0"
    line = Master::CLI::RuntimeMode.summary(config: { "web_token" => "" })
    assert_includes line, "safe"
    assert_includes line, "visitor"
    assert_includes line, "cli"
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

require_relative "test_helper"

class TestRuntimeNativeInventory < Minitest::Test
  FakeSpec = Struct.new(:name, :version, :extensions, :metadata)

  def test_native_requires_declared_extensions
    native = FakeSpec.new("native_gem", "1.0.0", ["ext/native/extconf.rb"], {})
    assert Master::Runtime::NativeInventory.native?(native)
  end

  def test_ractor_safety_defaults_to_unknown
    spec = FakeSpec.new("native_gem", "1.0.0", ["ext/native/extconf.rb"], {})
    assert_equal "unknown", Master::Runtime::NativeInventory.ractor_safety(spec)
  end

  def test_explicit_ractor_metadata_is_respected
    safe = FakeSpec.new("safe_gem", "1.0.0", ["ext/native/extconf.rb"], { "ractor_safe" => "true" })
    unsafe = FakeSpec.new("unsafe_gem", "1.0.0", ["ext/native/extconf.rb"], { "ractor_safe" => "false" })

    assert_equal "safe", Master::Runtime::NativeInventory.ractor_safety(safe)
    assert_equal "unsafe", Master::Runtime::NativeInventory.ractor_safety(unsafe)
  end
end

require "minitest/autorun"

class TestRuntimeOneSource < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_release_check_delegates_runtime_selection
    source = read("../MASTER/checks/release.rb")
    assert_includes source, 'require_relative "../../MASTER/lib/operator/ruby_runner"'
    assert_includes source, "[Operator::RubyRunner.ruby_cmd]"
    assert_includes source, "Operator::RubyRunner.bundle_cmd"
    refute_match(/\["ruby\d+"\]/, source)
  end

  def test_css_builder_delegates_bundle_selection
    source = read("../MASTER/tools/rails/build_all_css.rb")
    # The tool lives in MASTER/tools/rails, two levels below MASTER/lib.
    assert_includes source, 'require_relative "../../lib/operator/ruby_runner"'
    assert_includes source, "Operator::RubyRunner.bundle_cmd"
    refute_includes source, '["rbenv", "exec", "bundle"]'
  end

  def test_style_check_delegates_bundler_and_ruby
    source = read("../MASTER/tools/style_check.rb")
    assert_includes source, 'require_relative "../lib/operator/ruby_runner"'
    assert_includes source, %([BUNDLE, "exec", RUBY, "-S", "rubocop")
    assert_includes source, %([BUNDLE, "exec", RUBY, shared_rubocop])
    refute_match(/which ruby\d+/, source)
  end
  def test_ruby_selectors_prefer_generic_ruby_and_discover_versioned_packages
    require_relative "../lib/operator/ruby_runner"
    assert_equal ["ruby"], Operator::RubyRunner::RUBY_NAMES
    wrapper = read("bin/ruby")
    openbsd = read("../OPENBSD/lib/ruby_select.sh")
    assert_includes wrapper, 'GENERIC_RUBY=$(command -v ruby'
    assert_includes wrapper, 'for ruby_path in "$directory"/ruby[0-9]*'
    assert_includes openbsd, '_rs_find ruby'
    assert_includes openbsd, '"$_rs_dir"/ruby[0-9]*'
    refute_includes wrapper, "ruby4.3 ruby43 ruby4.2"
    refute_includes openbsd, "ruby4.0 ruby40"
  end
end

require_relative "test_helper"

class TestRuntimeRegexpTimeout < Minitest::Test
  def test_runtime_installs_a_configurable_regexp_timeout
    previous_timeout = Regexp.timeout
    previous_env = ENV["MASTER_REGEXP_TIMEOUT"]
    ENV["MASTER_REGEXP_TIMEOUT"] = "0.25"

    Master.send(:install_regexp_timeout!)

    assert_in_delta 0.25, Regexp.timeout, 0.001
  ensure
    previous_env.nil? ? ENV.delete("MASTER_REGEXP_TIMEOUT") : ENV["MASTER_REGEXP_TIMEOUT"] = previous_env
    Regexp.timeout = previous_timeout
  end

  def test_invalid_timeout_falls_back_to_the_runtime_default
    previous_timeout = Regexp.timeout
    previous_env = ENV["MASTER_REGEXP_TIMEOUT"]
    ENV["MASTER_REGEXP_TIMEOUT"] = "not-a-number"

    Master.send(:install_regexp_timeout!)

    assert_in_delta Master::MasterRuntime::REGEXP_TIMEOUT_S, Regexp.timeout, 0.001
  ensure
    previous_env.nil? ? ENV.delete("MASTER_REGEXP_TIMEOUT") : ENV["MASTER_REGEXP_TIMEOUT"] = previous_env
    Regexp.timeout = previous_timeout
  end

  def test_pathological_regexp_is_interrupted
    previous_timeout = Regexp.timeout
    Regexp.timeout = 0.01

    error = assert_raises(Regexp::TimeoutError) do
      /^(a|a)+$/.match?("a" * 100_000 + "x")
    end

    assert_kind_of Regexp::TimeoutError, error
  ensure
    Regexp.timeout = previous_timeout
  end
end
