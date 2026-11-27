# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# .master/config.yml merges over DEFAULTS, so a misspelled key is kept and never
# read: `budget_mx: 2` leaves the $10 default spending with nothing said.
class TestGroundConfig < Minitest::Test
  def config_with(yaml)
    Dir.mktmpdir("ground_config") do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      File.write(File.join(root, ".master", "config.yml"), yaml)
      config = nil
      _out, err = capture_io { config = Master::Ground::Config.new(root) }
      yield config, err, root
    end
  end

  def test_a_near_miss_on_a_known_key_is_named_at_load_and_by_validate
    config_with("budget_mx: 2\n") do |config, err|
      assert_match(/'budget_mx' is not read; did you mean 'budget_max'/, err) # source-assertion: ok — the warning written to stderr, not a source file
      assert_includes config.validate.join, "did you mean 'budget_max'"
      assert_in_delta Master::Ground::Config::BUDGET_MAX_DEFAULT, config.budget_max
    end
  end

  # The web tier and pairing keep their own keys here, so only a near miss is
  # a finding; an unrelated key and a short one two edits away are not.
  def test_legacy_opus_preference_migrates_once_to_routed_default
    config_with("model: claude-opus-5-5\n") do |config, err, root|
      assert_equal Master::Ground::Config::DEFAULTS["model"], config.model
      assert_match(/migrated legacy model preference/, err)
      persisted = YAML.safe_load_file(File.join(root, ".master", "config.yml"), aliases: true)
      assert_equal Master::Ground::Config::DEFAULTS["model"], persisted.fetch("model")
      assert_equal true, persisted.fetch("model_preference_migrated")

      config["model"] = "claude-opus-5-5"
      config.save!
      again = Master::Ground::Config.new(root)
      assert_equal "claude-opus-5-5", again.model
    end
  end

  def test_an_unrelated_key_is_not_a_typo
    config_with("web_token: abc\nroot: /srv\npersona: anchor\n") do |config, err|
      assert_empty err
      assert config.valid?, config.validate.join("; ")
    end
  end

  # One config for every checkout: a shared file beside ~/.config/master/env wins over a
  # checkout's .master/config.yml, MASTER_CONFIG wins over both, and migration moves the
  # checkout file across verified, keeping the original as .migrated.
  def test_the_shared_config_serves_every_checkout_once_migrated
    Dir.mktmpdir("config_home") do |home|
      with_env("XDG_CONFIG_HOME" => home) do
        config_with("model: checkout-model\n") do |_config, _err, root|
          assert_equal File.join(root, ".master", "config.yml"), MasterPaths.config_file(root:)

          assert_match(/moved/, Master::Ground::Config.migrate_to_shared!(root))
          assert_equal File.join(home, "master", "config.yml"), MasterPaths.config_file(root:)
          assert_equal "checkout-model", Master::Ground::Config.new(root)["model"]
          assert File.file?(File.join(root, ".master", "config.yml.migrated"))
          assert_match(/already exists/, Master::Ground::Config.migrate_to_shared!(root))
        end
      end
    end
  end

  def test_master_config_names_the_file_outright
    Dir.mktmpdir("explicit") do |dir|
      path = File.join(dir, "elsewhere.yml")
      with_env("MASTER_CONFIG" => path) { assert_equal path, MasterPaths.config_file(root: dir) }
    end
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV[key]] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end

require_relative "test_helper"
require "tmpdir"
require "fileutils"

# The order is the tree-wide trend line: total tagged violations across lib/,
# and the delta since the last run. It answered Err("undefined local variable
# or method 'report'") on every call it had ever been given, so what these pin
# is that it runs at all, and that the second run can read what the first wrote.
class ConstitutionDriftTest < Minitest::Test
  FakeScanner = Struct.new(:findings) do
    def scan(_path, depth: :deep) = Master::Result.ok(findings)
  end

  def setup
    @tmp = Dir.mktmpdir("constitution_drift_test")
    FileUtils.mkdir_p(File.join(@tmp, "lib"))
    File.write(File.join(@tmp, "lib", "example.rb"), "x = 1\n")
  end

  def teardown = FileUtils.remove_entry(@tmp)

  def order(findings)
    Master::Ground::Orders::ConstitutionDrift.new(
      container: { scanner: FakeScanner.new(findings), root: @tmp },
    )
  end

  def finding(tags) = { tags: }

  def test_it_reports_a_total_and_a_first_run_delta
    result = order([finding(%i[READABILITY]), finding(%i[CLEAN_CODE])]).call

    assert_predicate result, :ok?
    assert_equal 2, result.value![:total]
    assert_equal 2, result.value![:delta]
  end

  def test_the_second_run_reads_what_the_first_persisted
    findings = [finding(%i[READABILITY])]
    order(findings).call

    assert_equal 0, order(findings).call.value![:delta]
  end

  def test_a_fall_reports_as_a_negative_delta
    order([finding(%i[READABILITY]), finding(%i[CLEAN_CODE])]).call

    assert_equal(-1, order([finding(%i[READABILITY])]).call.value![:delta])
  end

  def test_it_names_the_worst_axiom
    result = order([finding(%i[READABILITY]), finding(%i[READABILITY]), finding(%i[CLEAN_CODE])]).call

    assert_equal "READABILITY", result.value![:worst]
  end

  def test_no_scanner_is_an_error_not_a_crash
    without = Master::Ground::Orders::ConstitutionDrift.new(container: { root: @tmp })

    assert_predicate without.call, :err?
  end
end

require_relative "test_helper"
require "master"
require_relative "../lib/ground/law_resolver"

# Conflict resolution follows document order in the canonical law catalogue.
class TestGroundLawResolver < Minitest::Test
  LAWS = {
    "TRUTHFUL_STATUS" => { "node" => "truthful_status", "statement" => "Truth precedes all." },
    "ROBUSTNESS" => { "node" => "robustness", "statement" => "Fail safely." },
    "ABSTRACTION" => { "node" => "abstraction", "statement" => "Keep boundaries sound." },
    "DENSITY" => { "node" => "density", "statement" => "Remove noise." },
  }.freeze

  INDEX = {
    "SAFE" => { "violates_law" => "ROBUSTNESS" },
    "TERSE" => { "supports_law" => "DENSITY" },
    "LAYERED" => { "tier" => "architecture" },
    "UNTIERED" => { "supports_law" => "DENSITY" },
  }.freeze

  def resolver = Master::Ground::LawResolver.new(laws_data: LAWS)

  def test_rule_serving_the_earlier_constitutional_node_wins_in_either_argument_order
    assert_equal "SAFE", resolver.winner("TERSE", "SAFE", laws_index: INDEX)
    assert_equal "SAFE", resolver.winner("SAFE", "TERSE", laws_index: INDEX)
  end

  def test_equal_node_keeps_the_first_rule
    assert_equal "TERSE", resolver.winner("TERSE", "UNTIERED", laws_index: INDEX)
    assert_equal "UNTIERED", resolver.winner("UNTIERED", "TERSE", laws_index: INDEX)
  end

  def test_tier_fallback_resolves_to_an_existing_parent_node
    assert_equal "ABSTRACTION", resolver.law_for("layered", laws_index: INDEX)
    assert_equal "DENSITY", resolver.law_for("UNTIERED", laws_index: INDEX)
  end

  def test_unknown_rule_or_law_comes_after_the_declared_nodes
    assert_nil resolver.law_for("NOPE", laws_index: INDEX)
    assert_equal 99, resolver.precedence_index(nil)
    assert_equal "LAYERED", resolver.winner("NOPE", "LAYERED", laws_index: INDEX)
  end

  def test_reads_order_from_laws_yml_without_numeric_priority_fields
    real = Master::Ground::LawResolver.new

    assert_equal 1, real.precedence_index("ROBUSTNESS")
    assert_equal 5, real.precedence_index("ABSTRACTION")
    assert_equal 6, real.precedence_index("DENSITY")
    refute Master.load_yaml(File.join(Master::ROOT, "data", "laws.yml")).values.any? { |row| row.is_a?(Hash) && row.key?("priority") }
  end

  def test_applicable_laws_always_include_all_nine_governing_nodes
    selection = Master::Ground::ApplicableLaws.new.for(path: File.join(Master::ROOT, "lib", "master.rb"))
    expected = Master::Ground::LawResolver.new.governing_law_ids

    assert_equal 9, expected.size
    expected.each do |law|
      assert_includes selection.governing_ids, law
      assert_includes selection.ids, law
    end
  end

  def test_applicable_laws_use_the_same_language_contract_as_the_scanner
    selection = Master::Ground::ApplicableLaws.new.for(path: File.join(Master::ROOT, "lib", "master.rb"))

    assert_equal "ruby", selection.language
    assert_includes selection.executable_ids, "FROZEN_STRING_LITERAL"
  end
end

require_relative "test_helper"

# LibraryVerify is the pre-flight Io::Shell and SelfTest run before trusting a
# gem, a path or a binary. A root with no Gemfile.lock cannot refuse a gem, so
# it answers ok rather than blocking every tree that is not a bundle.
class TestGroundLibraryVerify < Minitest::Test
  def setup
    @root = Dir.mktmpdir("library_verify_")
    File.write(File.join(@root, "Gemfile.lock"), "GEM\n  specs:\n    prism (1.4.0)\n    zeitwerk (2.7.2)\n")
    @verify = Master::Ground::LibraryVerify.new(root: @root)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_gems_are_checked_by_name_and_optionally_by_exact_version
    assert @verify.verify_gem!("prism").ok?
    assert @verify.verify_gem!("prism", version: "1.4.0").ok?
    refute @verify.verify_gem!("prism", version: "1.4").ok?, "a version prefix is not the version"
    refute @verify.verify_gem!("pris").ok?, "a name prefix is not the gem"
    assert_equal :validation, @verify.verify_gem!("rails").category
  end

  def test_a_root_without_a_lock_cannot_refuse_a_gem
    bare = Dir.mktmpdir("library_verify_bare_")

    assert Master::Ground::LibraryVerify.new(root: bare).verify_gem!("anything").ok?
  ensure
    FileUtils.rm_rf(bare)
  end

  def test_paths_resolve_against_the_root
    assert_equal File.join(@root, "Gemfile.lock"), @verify.verify_path!("Gemfile.lock").value!
    refute @verify.verify_path!("missing/file.rb").ok?
  end

  def test_binaries_are_looked_up_on_path_and_not_executed
    assert @verify.verify_binary!("ruby").ok?
    refute @verify.verify_binary!("no-such-binary-#{Process.pid}").ok?
    refute @verify.verify_binary!("ruby; touch #{File.join(@root, 'pwned')}").ok?
    refute File.exist?(File.join(@root, "pwned")), "the name is escaped, never run"
  end
end

require_relative "test_helper"
require "master"

# Ground::Orders::AggressiveMerge, the standing order that flags thin siblings
# and low-density names on every write.
class TestGroundOrdersAggressiveMerge < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("aggressive_merge")
    @bus = Master::Trace::EventBus.new
    @events = []
    @bus.subscribe("aggressive_merge:candidate") { |ev| @events << ev }
    @tracker = Master::Trace::WriteTracker.new(event_bus: @bus)
    Master::Trace::WriteTracker.current = @tracker
    @container = { bus: @bus, root: @dir, event: nil }
  end

  def teardown
    Master::Trace::WriteTracker.current = nil
    FileUtils.remove_entry(@dir)
  end

  def test_flags_support_suffix_for_merge
    write("lib/foo.rb", "# frozen_string_literal: true\nmodule Foo; end\n")
    support = write("lib/foo_support.rb", "# frozen_string_literal: true\nmodule FooSupport; end\n")
    @container[:event] = { path: support }

    result = order.call
    assert result.ok?
    merge = @events.find { |ev| ev[:action] == "merge" && ev[:from] == "lib/foo_support.rb" }
    assert merge, "expected merge candidate for foo_support.rb"
    assert_equal "lib/foo.rb", merge[:to]
  end

  def test_flags_low_density_slug_for_rename
    path = write("lib/misc_util_helper.rb", "# frozen_string_literal: true\nmodule MiscUtilHelper; end\n")
    @container[:event] = { path: }

    result = order.call
    assert result.ok?
    rename = @events.find { |ev| ev[:action] == "rename" && ev[:from] == "lib/misc_util_helper.rb" }
    assert rename, "expected parameterized slug rename candidate"
    assert_match(/filler-only|low-density/i, rename[:reason])
  end

  def test_flags_thin_sibling_for_merge
    write("lib/widget.rb", "# frozen_string_literal: true\nmodule Widget; end\n")
    extra = write("lib/widget_extra.rb", "# frozen_string_literal: true\nmodule WidgetExtra; end\n")
    @container[:event] = { path: extra }

    result = order.call
    assert result.ok?
    merge = @events.find { |ev| ev[:action] == "merge" && ev[:from] == "lib/widget_extra.rb" }
    assert merge, "expected thin sibling merge candidate"
  end

  private

  def order
    Master::Ground::Orders::AggressiveMerge.new(container: @container)
  end

  def write(rel, body)
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    Master::Trace::WriteTracker.current&.record(path)
    path
  end
end

require_relative "test_helper"
require "open3"
require "digest"

class GroundRedactorTest < Minitest::Test
  def test_text_redacts_api_key_patterns
    raw = "token sk-#{'A' * 24} leaked"
    assert_equal "token [REDACTED] leaked", Master::Ground::Redactor.text(raw)
  end

  def test_text_redacts_github_personal_access_token_prefixes
    %w[ghp_ gho_ ghu_ ghs_ ghr_ github_pat_].each do |prefix|
      raw = "credential #{prefix}#{'A' * 36} leaked"
      assert_equal "credential [REDACTED] leaked", Master::Ground::Redactor.text(raw), prefix
    end
  end

  def test_text_does_not_reenter_through_a_string_subclass
    klass = Class.new(String) do
      define_method(:to_s) { Master::Ground::Redactor.text(self) }
      define_method(:to_str) { Master::Ground::Redactor.text(self) }
      define_method(:gsub) { |*args| Master::Ground::Redactor.text(self) }
    end
    raw = klass.new("token sk-#{'A' * 24} leaked")

    assert_equal "token [REDACTED] leaked", Master::Ground::Redactor.text(raw)
  end

  def test_text_normalizes_string_returned_by_to_s
    string_class = Class.new(String) do
      define_method(:to_str) { Master::Ground::Redactor.text(self) }
    end
    value_class = Class.new do
      define_method(:to_s) { string_class.new("token sk-#{'D' * 24}") }
    end

    assert_equal "token [REDACTED]", Master::Ground::Redactor.text(value_class.new)
  end

  def test_text_redacts_bearer_tokens
    raw = "authorization Bearer #{'F' * 24}"
    assert_equal "authorization [REDACTED]", Master::Ground::Redactor.text(raw)
  end

  def test_text_survives_hostile_string_search_methods
    script = <<~'RUBY'
      require "ground/redactor"

      module HostileStringMethods
        def index(*)
          Master::Ground::Redactor.text(self)
        end

        def downcase(*)
          Master::Ground::Redactor.text(self)
        end
      end

      String.prepend(HostileStringMethods)

      raw = "authorization Bearer FFFFFFFFFFFFFFFFFFFFFFFF"
      expected = "authorization [REDACTED]"
      abort Master::Ground::Redactor.text(raw) unless Master::Ground::Redactor.text(raw) == expected
    RUBY

    output, status = Open3.capture2e(
      RbConfig.ruby,
      "-I#{File.expand_path("../lib", __dir__)}",
      "-e", script
    )
    assert status.success?, output
  end

  def test_text_reentry_guard_survives_fiber_boundary
    script = <<~'RUBY'
      require "ground/redactor"

      module HostileStringMethods
        def bytesize(*)
          Fiber.new { Master::Ground::Redactor.text(self) }.resume
          super
        end
      end

      String.prepend(HostileStringMethods)

      raw = "plain text without a secret"
      actual = Master::Ground::Redactor.text(raw)
      abort actual unless actual == raw
    RUBY

    output, status = Open3.capture2e(
      RbConfig.ruby,
      "-I#{File.expand_path("../lib", __dir__)}",
      "-e", script
    )
    assert status.success?, output
  end

  def test_text_survives_hostile_core_string_dispatch
    script = <<~'RUBY'
      require "ground/redactor"

      module HostileStringMethods
        def bytesize(*)
          Master::Ground::Redactor.text(self)
        end

        def getbyte(*)
          Master::Ground::Redactor.text(self)
        end

        def byteslice(*)
          Master::Ground::Redactor.text(self)
        end

        def length(*)
          Master::Ground::Redactor.text(self)
        end

        def [](*)
          Master::Ground::Redactor.text(self)
        end

        def +(other)
          Master::Ground::Redactor.text(self)
        end
      end

      String.prepend(HostileStringMethods)

      raw = "authorization Bearer FFFFFFFFFFFFFFFFFFFFFFFF"
      expected = "authorization [REDACTED]"
      actual = Master::Ground::Redactor.text(raw)
      abort actual unless actual == expected
    RUBY

    output, status = Open3.capture2e(
      RbConfig.ruby,
      "-I#{File.expand_path("../lib", __dir__)}",
      "-e", script
    )
    assert status.success?, output
  end

  def test_text_redacts_long_bare_alphanumeric_tokens
    raw = "value #{'G' * 32}"
    assert_equal "value [REDACTED]", Master::Ground::Redactor.text(raw)
  end

  def test_payload_accepts_keyword_fields
    scrubbed = Master::Ground::Redactor.payload(text: "sk-#{'C' * 24}")

    assert_equal "[REDACTED]", scrubbed[:text]
  end

  def test_payload_preserves_sha256_digest_metadata_without_relaxing_secret_redaction
    digest = Digest::SHA256.hexdigest("private source location")
    secret = "G" * 64

    scrubbed = Master::Ground::Redactor.payload(
      path_digest: digest,
      scope_digest: digest,
      text: secret,
    )

    assert_equal digest, scrubbed[:path_digest]
    assert_equal digest, scrubbed[:scope_digest]
    assert_equal "[REDACTED]", scrubbed[:text]
  end

  def test_payload_terminates_on_a_self_referential_hash
    raw = {}
    raw[:child] = raw

    scrubbed = Master::Ground::Redactor.payload(raw)

    assert_equal "[CYCLE]", scrubbed[:child]
  end

  def test_payload_terminates_on_a_self_referential_array
    raw = []
    raw << raw

    scrubbed = Master::Ground::Redactor.payload({ value: raw })

    assert_equal "[CYCLE]", scrubbed[:value][0]
  end

  def test_payload_terminates_on_a_hash_array_hash_cycle
    hash = {}
    array = []
    hash[:array] = array
    array << hash

    scrubbed = Master::Ground::Redactor.payload(hash)

    assert_equal "[CYCLE]", scrubbed[:array][0]
  end

  def test_payload_bounds_extreme_nesting
    raw = {}
    cursor = raw
    1_000.times do
      cursor[:child] = {}
      cursor = cursor[:child]
    end

    scrubbed = Master::Ground::Redactor.payload(raw)

    cursor = scrubbed
    15.times { cursor = cursor[:child] }
    assert_equal "[DEPTH]", cursor[:child]
  end

  def test_payload_bounds_extreme_array_nesting
    raw = []
    cursor = raw
    1_000.times do
      cursor << []
      cursor = cursor[0]
    end

    scrubbed = Master::Ground::Redactor.payload({ value: raw })

    cursor = scrubbed[:value]
    14.times { cursor = cursor[0] }
    assert_equal "[DEPTH]", cursor[0]
  end

  def test_payload_redacts_note_text_and_sensitive_keys
    scrubbed = Master::Ground::Redactor.payload(
      text: "sk-#{'B' * 24}",
      token: "secret-value",
      tool: "ReadFile",
    )

    assert_equal "[REDACTED]", scrubbed[:text]
    assert_equal "[REDACTED]", scrubbed[:token]
    assert_equal "ReadFile", scrubbed[:tool]
  end
end

require_relative "test_helper"

class TestRuntimeCatalog < Minitest::Test
  def setup
    Master::Ground::RuntimeCatalog.clear_cache!
  end

  def test_load_all_sections
    assert_path_exists Master::Ground::RuntimeCatalog::CATALOG_PATH
    refute_path_exists File.join(Master::ROOT, "data", "runtime"), "runtime catalog must remain consolidated"

    sections = Master::Ground::RuntimeCatalog.sections

    assert_includes sections, "runtime", "web_boot_payload reads this section twice"
    assert_includes sections, "tts_phrases", "TtsController reads this section"

    sections.each do |section|
      data = Master::Ground::RuntimeCatalog.load(section)
      assert_kind_of Hash, data, "expected hash for #{section}"
      refute_empty data, "expected non-empty #{section}"
    end
  end

  def test_catalog_refreshes_after_same_process_edit
    Dir.mktmpdir("runtime_catalog_refresh") do |root|
      path = File.join(root, "runtime.yml")
      File.write(path, "probe:\n  marker: first\n")

      catalog = Master::Ground::RuntimeCatalog
      original_path = catalog.const_get(:CATALOG_PATH)
      catalog.send(:remove_const, :CATALOG_PATH)
      catalog.const_set(:CATALOG_PATH, path)

      begin
        catalog.clear_cache!
        assert_equal "first", catalog.load("probe").fetch("marker")

        File.write(path, "probe:\n  marker: second\n")

        assert_equal "second", catalog.load("probe").fetch("marker")
      ensure
        catalog.send(:remove_const, :CATALOG_PATH)
        catalog.const_set(:CATALOG_PATH, original_path)
        catalog.clear_cache!
      end
    end
  ensure
    Master::Ground::RuntimeCatalog.clear_cache!
  end

  def test_enhancements_filter_by_area_and_tier
    all = Master::Ground::RuntimeCatalog.enhancements
    assert all.size > 100

    face = Master::Ground::RuntimeCatalog.enhancements(area: "face")
    assert face.all? { |item| item["area"] == "face" }

    p0 = Master::Ground::RuntimeCatalog.enhancements(tier: "p0")
    assert p0.all? { |item| item["tier"] == "p0" }
    assert p0.any? { |item| item["status"] == "implemented" }
  end

  def test_micro_interactions_count_and_lookup
    items = Master::Ground::RuntimeCatalog.micro_interactions
    assert_equal 80, items.size

    entry = Master::Ground::RuntimeCatalog.micro_interaction("mi_042")
    assert_equal "escape emits user:interrupt", entry["summary"]
  end

  def test_web_boot_payload_shape
    payload = Master::Ground::RuntimeCatalog.web_boot_payload

    assert_equal "/runtime/topologies", payload[:topologies_path]
    assert payload[:enhancements_pending_count].is_a?(Integer)
    assert payload[:micro_interactions].is_a?(Array)
    assert payload[:event_registry].is_a?(Hash)
    assert payload[:visual_limits].is_a?(Hash)
    assert payload[:tts_config].is_a?(Hash)
    assert payload[:topologies].is_a?(Hash)
  end

  def test_web_boot_payload_minimal_shape
    payload = Master::Ground::RuntimeCatalog.web_boot_payload_minimal

    assert_equal "/runtime/topologies", payload[:topologies_path]
    assert_equal "/runtime/config", payload[:config_path]
    assert payload[:enhancements_pending_count].is_a?(Integer)
    assert payload[:enhancements].is_a?(Array)
    # The payload's contract is that it reports a real aesthetic, not a
    # particular one, so the house default can change without this going red.
    assert_includes Master::Voice::Aesthetic::MODES, payload[:aesthetic]
    refute payload.key?(:topologies)
  end

  # Through `load`, the one documented door: the sections and the shape they
  # promise are the contract, not a named reader per section.
  def test_invariants_and_event_registry
    inv = Master::Ground::RuntimeCatalog.load("invariants")
    assert inv["invariants"].is_a?(Array)
    assert inv["anti_patterns"].is_a?(Array)

    registry = Master::Ground::RuntimeCatalog.load("event_registry")
    assert registry["namespaces"].is_a?(Array)
    assert registry["established_events"].is_a?(Array)
  end
end

require_relative "test_helper"
require "fileutils"

# StandingOrders is the runtime's autonomous scheduler: it decides, unattended,
# which commands run and how often, including event-triggered ones with regex filters.
#
# STATE_PATH is a constant under the real .master/, so the file is saved and put
# back: a test must not silently reset the operator's live order state.
class StandingOrdersTest < Minitest::Test
  Orders = Master::Ground::StandingOrders

  KEPT = [Orders::STATE_PATH, Master::Ground::Tool::Domain::CONSENT_PATH].freeze

  def setup
    @state_path = Orders::STATE_PATH
    @saved = KEPT.to_h { |path| [path, File.file?(path) ? File.binread(path) : nil] }
    @orders = Orders.new
  end

  RecordingBus = Struct.new(:events) do
    def publish(name, **payload)
      events << [name, payload]
    end
  end

  def bus_on_orders
    bus = RecordingBus.new([])
    @orders.instance_variable_set(:@bus, bus)
    bus
  end

  def teardown
    @saved.each do |path, bytes|
      if bytes
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, bytes)
      elsif File.file?(path)
        File.delete(path)
      end
    end
  end

  def order(overrides = {})
    {
      "name" => "test_order", "description" => "d", "trigger" => "scheduled",
      "interval_s" => 60, "command" => "noop", "enabled" => true,
      "state" => "pending", "last_run_at" => 0
    }.merge(overrides)
  end

  def with_orders(list)
    previous = @orders.instance_variable_get(:@orders)
    @orders.instance_variable_set(:@orders, list)
    yield
  ensure
    @orders.instance_variable_set(:@orders, previous)
  end

  def test_availability_posture_reports_degraded_as_ok_so_it_keeps_waking
    agent = Object.new
    router = Object.new
    router.define_singleton_method(:pool) { |wait:| [] }
    agent.define_singleton_method(:model_router) { router }
    bus = RecordingBus.new([])

    callable = Master::Ground::Orders::AvailabilityPosture.new(container: { agent:, root: Master::ROOT, bus: })
    result = callable.call

    assert_predicate result, :ok?
    assert_equal false, result.value!.fetch(:reachable)
    assert_equal true, result.value!.fetch(:degraded)
    assert bus.events.any? { |event| event.first == "availability:posture" && event.last[:degraded] }
  end

  def test_availability_posture_order_reports_ladder_levels_without_mutation
    agent = Object.new
    router = Object.new
    router.define_singleton_method(:pool) { |wait:| %w[ollama:qwen3 web-chat:grok] }
    agent.define_singleton_method(:model_router) { router }
    bus = Struct.new(:events) do
      def publish(name, **payload)
        events << [name, payload]
      end

      # StandingOrders subscribes to its events when it is built.
      def subscribe(_name) = nil
    end.new([])
    orders = Orders.new(pipeline: nil, event_bus: bus)
    orders.wire_container(agent:, root: Master::ROOT, bus:)

    callable = Master::Ground::Orders::AvailabilityPosture.new(container: { agent:, root: Master::ROOT, bus: })
    result = callable.call

    assert_predicate result, :ok?
    assert_equal "L2", result.value!.fetch(:floor)
    assert_equal true, result.value!.fetch(:reachable)
    assert_equal 1, result.value!.fetch(:levels).fetch("L2")
    assert_equal 1, result.value!.fetch(:levels).fetch("L3")
    assert bus.events.any? { |event| event.first == "availability:posture" }
  end

  def test_state_of_parks_an_unknown_state
    assert_equal "pending", @orders.send(:state_of, order)
    assert_equal "error", @orders.send(:state_of, order("state" => "nonsense"))
    assert_equal "error", @orders.send(:state_of, order("state" => nil))
    Orders::VALID_STATES.each { |state| assert_equal state, @orders.send(:state_of, order("state" => state)) }
  end

  def test_due_requires_enabled_scheduled_and_an_elapsed_interval
    stale = order("name" => "stale", "last_run_at" => Time.now.to_i - 120)
    fresh = order("name" => "fresh", "last_run_at" => Time.now.to_i)
    disabled = order("name" => "off", "enabled" => false, "last_run_at" => 0)
    evented = order("name" => "evented", "trigger" => "event", "last_run_at" => 0)

    with_orders([stale, fresh, disabled, evented]) do
      assert_equal %w[stale], @orders.due.map { |o| o["name"] }
    end
  end

  def test_due_can_be_scoped_to_one_owner
    mine = order("name" => "mine", "owner" => "owner123")
    theirs = order("name" => "theirs", "owner" => "operator")

    with_orders([mine, theirs]) do
      assert_equal ["mine"], @orders.due(owner: "owner123").map { |o| o["name"] }
      assert_equal %w[mine theirs], @orders.due.map { |o| o["name"] }
    end
  end

  # An errored order waits for /orders reset, and "running" must not be picked up
  # twice.
  def test_due_skips_running_and_errored_orders
    with_orders([order("name" => "running", "state" => "running"),
                 order("name" => "errored", "state" => "error"),
                 order("name" => "done", "state" => "done")]) do
      assert_equal %w[done], @orders.due.map { |o| o["name"] }
    end
  end

  # A process that died mid-run left "running" on disk. The next boot must say
  # the run did not finish, rather than leave it running forever or call it done.
  def test_a_run_interrupted_by_a_restart_is_reported_not_left_running
    carried = { "test_order" => { "state" => "running", "last_run_at" => 7 },
                "idle" => { "state" => "done", "last_run_at" => 7 } }

    @orders.stub(:read_defs, [order, order("name" => "idle")]) do
      @orders.stub(:read_state, carried) do
        restored = @orders.send(:load_orders)

        assert_equal "error", restored.first["state"]
        assert_match(/interrupted/, restored.first["last_error"])
        assert_equal "done", restored.last["state"], "only a carried running state is an interruption"
      end
    end
  end

  def test_upsert_creates_then_updates_in_place
    with_orders([]) do
      @orders.upsert(name: "nightly", description: "first", command: "scan")
      list = @orders.instance_variable_get(:@orders)

      assert_equal 1, list.size
      assert_equal "pending", list.first["state"]

      @orders.upsert(name: "nightly", description: "second", command: "scan", interval_s: 7200)

      assert_equal 1, @orders.instance_variable_get(:@orders).size
      assert_equal "second", @orders.instance_variable_get(:@orders).first["description"]
      assert_equal 7200, @orders.instance_variable_get(:@orders).first["interval_s"]
    end
  end

  def test_enable_disable_and_reset_report_a_missing_order
    with_orders([]) do
      assert_equal "no order named 'ghost'", @orders.enable("ghost")
      assert_equal "no order named 'ghost'", @orders.disable("ghost")
      assert_equal "no order named 'ghost'", @orders.reset("ghost")
    end
  end

  def test_reset_clears_state_and_the_last_error
    subject = order("state" => "error", "last_error" => "boom")
    with_orders([subject]) do
      assert_match(/reset/, @orders.reset("test_order"))
      assert_equal "pending", subject["state"]
      refute subject.key?("last_error")
    end
  end

  def test_toggle_flips_enabled
    subject = order
    with_orders([subject]) do
      @orders.disable("test_order")
      refute subject["enabled"]
      @orders.enable("test_order")
      assert subject["enabled"]
    end
  end

  def test_list_and_format_describe_state_flag_and_error
    subject = order("enabled" => false, "state" => "error", "last_error" => "x" * 80,
                    "last_run_at" => Time.new(2026, 1, 2).to_i)
    with_orders([subject]) do
      line = @orders.list

      assert_includes line, "off|error"
      assert_includes line, "2026-01-02"
      assert_includes line, "!!"
      assert_equal 60, line[/!! (x+)/, 1].length, "the error is truncated for display"
    end
  end

  def test_list_says_so_when_empty
    with_orders([]) { assert_equal "no standing orders defined", @orders.list }
  end

  def test_event_match_needs_enabled_event_trigger_and_the_right_name
    evented = order("trigger" => "event", "event" => "tool:after")

    assert @orders.send(:event_match?, evented, "tool:after", {})
    refute @orders.send(:event_match?, evented, "tool:before", {})
    refute @orders.send(:event_match?, order("event" => "tool:after"), "tool:after", {})
    refute @orders.send(:event_match?, evented.merge("enabled" => false), "tool:after", {})
  end

  def test_filter_and_exclude_are_regexes_over_the_payload
    subject = order("trigger" => "event", "event" => "tool:after", "filter" => "write_file")

    assert @orders.send(:event_match?, subject, "tool:after", { tool: "write_file" })
    refute @orders.send(:event_match?, subject, "tool:after", { tool: "read_file" })

    excluded = subject.merge("exclude" => "spec/")
    refute @orders.send(:event_match?, excluded, "tool:after", { tool: "write_file", path: "spec/x.rb" })
    assert @orders.send(:event_match?, excluded, "tool:after", { tool: "write_file", path: "lib/x.rb" })
  end

  def test_invalid_filter_is_ignored_and_reported
    subject = order("trigger" => "event", "event" => "tool:after", "filter" => "[")

    bus = bus_on_orders

    refute @orders.send(:filter_match?, subject, { tool: "write_file" })
    assert bus.events.any? { |event| event.first == "standing_order:invalid_filter" }
  end

  def test_invalid_exclude_is_ignored_and_reported
    subject = order("trigger" => "event", "event" => "tool:after", "exclude" => "[")

    bus = bus_on_orders

    refute @orders.send(:exclude_match?, subject, { tool: "write_file" })
    assert bus.events.any? { |event| event.first == "standing_order:invalid_exclude" }
  end

  def test_an_empty_filter_matches_everything
    assert @orders.send(:filter_match?, order, {})
    refute @orders.send(:exclude_match?, order, {})
  end

  def test_debounce_blocks_a_rerun_inside_the_window
    assert @orders.send(:debounced?, order("last_run_at" => Time.now.to_i))
    refute @orders.send(:debounced?, order("last_run_at" => Time.now.to_i - Orders::DEBOUNCE_S - 1))
    refute @orders.send(:debounced?, order("last_run_at" => 0)), "never-run orders are not debounced"
  end

  def test_an_unknown_callable_is_an_error_not_an_exception
    result = @orders.send(:execute_order, order("callable" => "no_such_order"))

    refute result.ok?
    assert_match(/unknown callable/, result.message)
  end

  def test_without_a_router_or_pipeline_execution_reports_no_router
    result = @orders.send(:execute_order, order)

    refute result.ok?
    assert_match(/no router/, result.message)
  end

  FakeStatus = Struct.new(:ok) do
    def success? = ok
  end

  def test_autocommit_pushes_after_a_successful_commit
    root = Dir.mktmpdir("master-autocommit-")
    bus = RecordingBus.new([])
    File.write(File.join(root, "file.rb"), "puts :ok\n")
    repo = File.expand_path("..", root)
    relative = File.join(File.basename(root), "file.rb")
    calls = []
    responses = [
      [" M file.rb\n", FakeStatus.new(true)],
      ["", FakeStatus.new(true)],
      ["", FakeStatus.new(true)],
    ]

    event = { path: File.join(root, "file.rb") }
    Master::Io::Exec.stub(:capture3, ->(*args, **) { calls << [:status, args]; [" M file.rb\n", nil, FakeStatus.new(true)] }) do
      Master::Io::Exec.stub(:capture2e, ->(*args, **) { calls << [:run, args]; responses.shift }) do
        result = Master::Ground::Orders::Autocommit.new(container: { root:, bus:, event: }).call

        assert result.ok?
        assert_equal true, result.value![:committed]
        assert_equal true, result.value![:pushed]
        assert_equal ["git", "-C", repo, "commit", "-m", "auto: standing-order commit (1 file(s))", "--", relative],
                     calls[1].last
        assert_equal ["git", "-C", File.expand_path("..", root), "push"], calls[2].last
        assert_equal [["autocommit:pushed", { files: 1, paths: [relative] }]], bus.events
      end
    end
  ensure
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end

  def test_autocommit_reports_a_push_failure_after_the_commit_lands
    root = Dir.mktmpdir("master-autocommit-")
    File.write(File.join(root, "file.rb"), "puts :ok\n")
    relative = File.join(File.basename(root), "file.rb")
    event = { path: File.join(root, "file.rb") }
    bus = RecordingBus.new([])
    # The commit, then the push: Autocommit commits path-scoped with no `git add` before it.
    responses = [
      ["", FakeStatus.new(true)],
      ["rejected\n", FakeStatus.new(false)],
    ]

    Master::Io::Exec.stub(:capture3, ->(*) { [" M file.rb\n", nil, FakeStatus.new(true)] }) do
      Master::Io::Exec.stub(:capture2e, ->(*) { responses.shift }) do
        result = Master::Ground::Orders::Autocommit.new(container: { root:, bus:, event: }).call

        assert result.ok?
        assert_equal true, result.value![:committed]
        assert_equal false, result.value![:pushed]
        assert_equal "rejected", result.value![:push_error]
        assert_equal [["autocommit:push_failed", { error: "rejected", paths: [relative] }]], bus.events
      end
    end
  ensure
    FileUtils.remove_entry(root) if root && Dir.exist?(root)
  end

  # A standing order commits with nobody watching, so it is held to git!'s refusal of a preserved asset.
  def preserved_asset_tree(repo)
    root = File.join(repo, "MASTER")
    FileUtils.mkdir_p(File.join(root, "data"))
    File.write(File.join(root, "data", "soul.yml"), "absolute: {}\n")
    FileUtils.mkdir_p(File.join(repo, "RAILS"))
    File.write(File.join(repo, "RAILS", "screenshot_review.png"), "png\n")
    root
  end

  # Runs Autocommit over a changed preserved screenshot with git stubbed; answers [result, the git calls that ran].
  def autocommit_preserved_asset(root, bus)
    ran = []
    status = FakeStatus.new(true)
    event = { path: File.join(root, "..", "RAILS", "screenshot_review.png") }

    result = Master::Io::Exec.stub(:capture3, ->(*) { [" M RAILS/screenshot_review.png\n", nil, status] }) do
      Master::Io::Exec.stub(:capture2e, ->(*args, **) { ran << args; ["", status] }) do
        Master::Ground::Orders::Autocommit.new(container: { root:, bus:, event: }).call
      end
    end
    [result, ran]
  end

  def test_autocommit_refuses_a_preserved_asset_before_git_runs
    repo = Dir.mktmpdir("master-autocommit-sacred-")
    bus = RecordingBus.new([])

    result, ran = autocommit_preserved_asset(preserved_asset_tree(repo), bus)

    assert_includes result.message, "screenshot_review.png is a preserved project asset"
    assert_empty ran, "neither the commit nor the push may run"
    assert_equal "autocommit:refused", bus.events.first&.first
  ensure
    FileUtils.remove_entry(repo) if repo && Dir.exist?(repo)
  end

  # /orders run executes whatever is due with nobody watching, so a hard reset,
  # a push or doas written as an order must never reach the router.
  def test_run_due_refuses_destructive_commands_before_routing
    routed = []
    pipeline = ->(input) { routed << input.value![:user_message]; Master::Result.ok("ran") }
    orders = Orders.new(pipeline:)
    list = ["git reset --hard origin/main", "git push origin main", "doas rcctl stop master", "scan"]
             .each_with_index.map { |cmd, i| order("name" => "o#{i}", "command" => cmd) }
    orders.instance_variable_set(:@orders, list)

    results = orders.run_due!

    assert_equal %w[scan], routed
    refused = results.reject { |r| r[:result].ok? }.map { |r| r[:name] }
    assert_equal %w[o0 o1 o2], refused
    assert_match(/standing order refused/, results.first[:result].message)
    assert_equal "error", list.first["state"]
  end

  def test_persist_writes_only_the_state_keys
    with_orders([order("state" => "done", "last_run_at" => 42, "last_error" => "e")]) do
      @orders.send(:persist)
      written = YAML.safe_load_file(@state_path)

      assert_equal %w[last_error last_run_at state], written.fetch("test_order").keys.sort
      assert_equal 42, written.dig("test_order", "last_run_at")
    end
  end

  def test_builtin_intervals_match_the_declared_constants
    assert_equal 86_400, Orders::DAILY_INTERVAL
    assert_equal 604_800, Orders::WEEKLY_INTERVAL
    intervals = Orders::BUILTIN_ORDERS.map { |o| o[:interval_s] }

    assert_includes intervals, Orders::WEEKLY_INTERVAL
    assert_equal Orders::DAILY_INTERVAL, @orders.send(:order_definition, "x", "help")["interval_s"]
  end

  # Every builtin order's command must be a word the registry answers; one that
  # is not reaches the model as chat on every wake. HELP_TOPICS is held to the
  # registry by test_command_registry_dispatch.
  def test_no_builtin_order_sends_a_word_no_command_answers
    words = Orders::BUILTIN_ORDERS.map { |o| o[:command].split.first }

    assert_empty words - Master::CLI::CommandRegistry::HELP_TOPICS.keys
  end

  # An objective is an order with an owner, a domain, a wake and a verify, and
  # it is still there, with what it has shown, after the process that set it
  # has gone.
  def objective(**fields)
    { name: "deploy_window", command: nil, domain: "coding", trigger: "heartbeat", interval_s: 0,
      verify: "echo window-open", owner: "johann" }.merge(fields)
  end

  def test_an_objective_added_at_runtime_survives_a_restart_with_its_evidence
    with_orders([]) do
      @orders.upsert(**objective)
      @orders.run_due!
    end

    restored = Orders.new.instance_variable_get(:@orders).find { |o| o["name"] == "deploy_window" }
    assert_equal %w[johann coding heartbeat], restored.values_at("owner", "domain", "trigger")
    assert_equal "verified", restored["state"]
    assert_equal "window-open", restored["evidence"].last["output"], "the check's own output is the evidence"
  end

  def test_the_heartbeat_wakes_an_objective_and_a_passing_verify_meets_it
    bus = Master::Trace::EventBus.new
    orders = Orders.new(event_bus: bus)
    orders.instance_variable_set(:@orders, [])
    orders.upsert(**objective)

    bus.publish("heartbeat:tick")

    met = orders.instance_variable_get(:@orders).first
    assert_equal "verified", met["state"]
    assert_empty orders.due, "a met objective stops waking"
  end

  def test_a_failing_verify_leaves_the_objective_waking_with_the_failure_on_record
    with_orders([]) do
      @orders.upsert(**objective(verify: "ruby -e exit(3)"))
      @orders.run_due!
      pending = @orders.instance_variable_get(:@orders).first

      assert_equal "done", pending["state"]
      refute pending["evidence"].last["ok"]
      assert_equal %w[deploy_window], @orders.due.map { |o| o["name"] }
    end
  end

  def test_finance_is_off_until_the_operator_consents
    FileUtils.rm_f(Master::Ground::Tool::Domain::CONSENT_PATH)
    with_orders([]) do
      @orders.upsert(**objective(domain: "finance"))
      @orders.run_due!
      refused = @orders.instance_variable_get(:@orders).first
      assert_equal "done", refused["state"]
      assert_match(/finance is off until the operator consents/, refused["evidence"].last["output"])

      Master::Ground::Tool::Domain.grant("finance")
      refused["last_run_at"] = 0
      @orders.run_due!
      assert_equal "verified", refused["state"]
    end
  end

  def test_a_consented_finance_objective_still_cannot_reach_the_coding_tools
    Master::Ground::Tool::Domain.grant("finance")
    routed = []
    orders = Orders.new(container: { commands: {}, memory: :shared_store })
    orders.instance_variable_set(:@orders, [])
    Master::CLI::TurnRouter.stub(:call, ->(**kw) { routed << kw }) do
      orders.upsert(**objective(domain: "finance", command: "write the budget", verify: nil, trigger: "scheduled"))
      result = orders.run_due!.first[:result]

      assert_empty routed
      assert_match(/finance cannot reach commands/, result.message)
    end
  end

  def test_a_domain_container_withholds_what_the_domain_does_not_reach
    full = { commands: :registry, agent: :agent, memory: :store, bus: :bus }
    Master::Ground::Tool::Domain.grant("household")

    assert_equal({ bus: :bus, domain: "household" }, Master::Ground::Tool::Domain.container("household", full))
    assert_equal full.merge(domain: "coding"), Master::Ground::Tool::Domain.container("coding", full)
  end

  def test_orders_add_reads_fields_whose_values_keep_their_spaces
    saved = []
    standing = Object.new.tap { |o| o.define_singleton_method(:upsert) { |**kw| saved << kw } }
    Master::CLI::CommandRegistry.add_order(standing, "name=tests domain=coding wake=heartbeat verify=env RAILS_ENV=test bundle exec rake test")

    assert_equal({ name: "tests", domain: "coding", trigger: "heartbeat", verify: "env RAILS_ENV=test bundle exec rake test", owner: "operator" },
                 saved.first)
    assert_match(/usage/, Master::CLI::CommandRegistry.add_order(standing, "domain=coding verify=true"))
  end
end

require_relative "test_helper"
require "digest"

class TestGroundTruth < Minitest::Test
  # laws.yml has no ground_truth_check key, so the default window must be positive
  # or every read is stale the moment it is recorded.
  def test_default_window_keeps_a_just_read_file_fresh
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "x = 1\n")
      gt = Master::Ground::Truth.new
      gt.record_read!(path)
      assert gt.fresh?(path)
    end
  end

  def test_records_and_asserts_fresh_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "x = 1\n")
      gt = Master::Ground::Truth.new(max_age_seconds: 60)
      gt.record_read!(path)
      assert gt.fresh?(path)
      stale = gt.assert_fresh!(path, reason: "claim_task_complete")
      assert stale.ok?
    end
  end

  def test_reads_from_an_earlier_turn_remain_fresh_but_cannot_authorize_current_turn_writes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "existing.txt")
      File.write(path, "original\n")
      truth = Master::Ground::Truth.new(max_age_seconds: 60)

      truth.record_read!(path)
      assert truth.fresh?(path)
      assert truth.fresh_in_current_turn?(path)
      previous_turn = truth.current_turn_id

      truth.begin_turn!

      assert_equal previous_turn + 1, truth.current_turn_id
      assert truth.fresh?(path), "age/content freshness remains available to non-write checks"
      refute truth.fresh_in_current_turn?(path), "a prior turn cannot authorize a replacement"
    end
  end

  def test_read_file_shows_the_whole_file_digest_for_a_bounded_slice
    Dir.mktmpdir do |dir|
      path = File.join(dir, "source.rb")
      content = (1..8).map { |line| "line #{line}\n" }.join
      File.write(path, content)
      truth = Master::Ground::Truth.new
      reader = Master::Io::ReadFile.new(root: dir, undo: nil, ground_truth: truth)

      result = reader.call(path: "source.rb", offset: 2, limit: 2)

      assert result.ok?, result.to_s
      assert_includes result.value!, "3\tline 3"
      assert_includes result.value!, "4\tline 4"
      refute_includes result.value!, "2\tline 2"
      assert_includes result.value!, 'path="source.rb"'
      assert_includes result.value!, "sha256=#{Digest::SHA256.hexdigest(content)}"
      assert_includes result.value!, "bytes=#{content.bytesize} lines=8 shown=2 offset=2 content=partial digest_scope=whole_file"
      assert truth.fresh?(path)
    end
  end

  def test_read_file_marks_a_complete_full_read
    Dir.mktmpdir do |dir|
      content = "first line\nsecond line\n"
      File.write(File.join(dir, "source.rb"), content)
      reader = Master::Io::ReadFile.new(root: dir, undo: nil)

      result = reader.call(path: "source.rb", full: true)

      assert result.ok?, result.to_s
      assert_includes result.value!, "1\tfirst line"
      assert_includes result.value!, "2\tsecond line"
      assert_includes result.value!, 'path="source.rb"'
      assert_includes result.value!, "sha256=#{Digest::SHA256.hexdigest(content)}"
      assert_includes result.value!, "content=full digest_scope=whole_file"
    end
  end

  def test_read_file_refreshes_an_expired_cached_receipt
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "source.rb"), "source\n")
      events = []
      bus = Object.new
      bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }
      truth = Master::Ground::Truth.new(max_age_seconds: -1, event_bus: bus)
      reader = Master::Io::ReadFile.new(root: dir, undo: nil, ground_truth: truth)

      first = reader.call(path: "source.rb")
      second = reader.call(path: "source.rb")

      assert first.ok?
      assert second.ok?
      assert_equal 2, events.count { |event, _| event == "ground_truth:read" }
    end
  end

  def test_read_file_refreshes_a_cached_receipt_at_the_start_of_a_new_turn
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "source.rb"), "source\n")
      events = []
      bus = Object.new
      bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }
      truth = Master::Ground::Truth.new(event_bus: bus)
      reader = Master::Io::ReadFile.new(root: dir, undo: nil, ground_truth: truth)

      first = reader.call(path: "source.rb")
      truth.begin_turn!
      second = reader.call(path: "source.rb")

      assert first.ok?
      assert second.ok?
      assert_equal 2, events.count { |event, _| event == "ground_truth:read" }
      assert truth.fresh_in_current_turn?(File.join(dir, "source.rb"))
    end
  end

  def test_read_file_does_not_report_success_when_ground_truth_receipt_fails
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "source.rb"), "source\n")
      truth = Object.new
      truth.define_singleton_method(:record_read!) { |*| nil }
      truth.define_singleton_method(:changed_since_read?) { |_| false }
      reader = Master::Io::ReadFile.new(root: dir, undo: nil, ground_truth: truth)

      result = reader.call(path: "source.rb")

      refute result.ok?
      assert_equal :infrastructure, result.category
      assert_match(/receipt could not be recorded/, result.message)
    end
  end

  # The read hash is the version a whole-file write was composed against, so a
  # file somebody changed afterwards is refused and a reread lets it through.
  def test_write_file_refuses_a_file_changed_since_it_was_read
    Dir.mktmpdir do |dir|
      gt = Master::Ground::Truth.new(max_age_seconds: 60)
      governor = Object.new
      def governor.permit?(*) = Master::Result.ok(true)
      undo = Master::Trace::Undo.new(session: Object.new.tap { |s| def s.snapshot(*) = nil }, root: dir)
      reader = Master::Io::ReadFile.new(root: dir, undo:, ground_truth: gt)
      writer = Master::Io::WriteFile.new(root: dir, undo:, governor:, ground_truth: gt)
      File.write(File.join(dir, "notes.txt"), "mine\n")

      reader.call(path: "notes.txt")
      assert writer.call(path: "notes.txt", content: "first\n").ok?, "a write after a read goes through"
      assert writer.call(path: "notes.txt", content: "second\n").ok?, "its own write does not make the file stale"

      File.write(File.join(dir, "notes.txt"), "theirs\n")
      refused = writer.call(path: "notes.txt", content: "third\n")
      assert_match(/changed since it was read/, refused.message.to_s)
      assert_equal "theirs\n", File.read(File.join(dir, "notes.txt"))

      reader.call(path: "notes.txt")
      assert writer.call(path: "notes.txt", content: "third\n").ok?, "a reread, even from the turn cache, clears it"
      assert writer.call(path: "fresh.txt", content: "new\n").ok?, "a file never read is not stale"
    end
  end

  def test_write_file_refuses_a_read_from_the_previous_turn
    Dir.mktmpdir do |dir|
      path = File.join(dir, "existing.txt")
      File.write(path, "original\n")
      truth = Master::Ground::Truth.new(max_age_seconds: 60)
      governor = Object.new
      def governor.permit?(*) = Master::Result.ok(true)
      undo = Master::Trace::Undo.new(session: Object.new.tap { |s| def s.snapshot(*) = nil }, root: dir)
      reader = Master::Io::ReadFile.new(root: dir, undo:, ground_truth: truth)
      writer = Master::Io::WriteFile.new(root: dir, undo:, governor:, ground_truth: truth)

      assert reader.call(path: "existing.txt").ok?
      truth.begin_turn!
      result = writer.call(path: "existing.txt", content: "replacement\n")

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/must be read in this turn/, result.message)
      assert_equal "original\n", File.read(path)
    end
  end

  def test_write_file_refuses_to_overwrite_an_existing_file_without_a_fresh_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, "existing.txt")
      File.write(path, "original\n")
      truth = Master::Ground::Truth.new
      governor = Object.new
      def governor.permit?(*) = Master::Result.ok(true)
      undo = Master::Trace::Undo.new(session: Object.new.tap { |s| def s.snapshot(*) = nil }, root: dir)
      writer = Master::Io::WriteFile.new(root: dir, undo:, governor:, ground_truth: truth)

      result = writer.call(path: "existing.txt", content: "replacement\n")

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/must be read in this turn/, result.message)
      assert_equal "original\n", File.read(path)
    end
  end

  def test_owned_write_receipt_is_not_mislabeled_as_a_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, "source.rb")
      File.write(path, "written by this turn\n")
      events = []
      bus = Object.new
      bus.define_singleton_method(:publish) { |event, **| events << event }
      truth = Master::Ground::Truth.new(event_bus: bus)

      truth.record_written!(path)

      assert_equal ["ground_truth:written"], events
      assert_empty truth.instance_variable_get(:@reads)
      assert truth.fresh_in_current_turn?(path), "an owned write is known in the current turn"
      refute truth.fresh?(path), "an owned write must not satisfy a source-read proof"
      assert truth.recorded_unchanged?(path)

      File.write(path, "changed by another writer\n")
      assert truth.changed_since_read?(path)
      refute truth.recorded_unchanged?(path)
    end
  end

  def test_stale_without_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "x = 1\n")
      gt = Master::Ground::Truth.new(max_age_seconds: 60)
      refute gt.fresh?(path)
      result = gt.assert_fresh!(path)
      assert result.err?
    end
  end
end

require_relative "test_helper"

# TypeChecker is the deterministic constraint pass FastStage runs before any
# model sees a file. Only Ruby that parses is checked, and each violation
# carries the complement that repairs it.
class TestGroundTypeChecker < Minitest::Test
  TC = Master::Ground::TypeChecker

  def rules(source, path: "a.rb") = TC.check(path, source).map(&:rule)

  def test_a_bare_rescue_is_flagged_and_a_typed_one_is_not
    bare = "# frozen_string_literal: true\nbegin\n  x\nrescue => e\n  y\nend\n"
    typed = "# frozen_string_literal: true\nbegin\n  x\nrescue StandardError => e\n  y\nend\n"

    assert_equal [:BARE_RESCUE], rules(bare)
    assert_empty rules(typed)
    assert_equal "rescue StandardError", TC.check("a.rb", bare).first.complement
  end

  def test_the_magic_comment_is_required
    assert_equal [:FROZEN_STRING_LITERAL], rules("x = 1\n")
  end

  def test_a_shebang_may_precede_the_magic_comment
    assert_empty rules("#!/usr/bin/env ruby\n# frozen_string_literal: true\nputs 1\n")
  end

  def test_other_languages_and_unparseable_ruby_are_skipped
    assert_empty rules("x = 1\n", path: "a.js")
    assert_empty rules("def (\n")
  end

  def test_a_registered_constraint_joins_the_walk
    checker = TC.new.register(:NO_PUTS) do |node, _src|
      next unless node.is_a?(Prism::CallNode) && node.name == :puts

      { message: "puts", complement: "logger" }
    end

    assert_equal [:NO_PUTS], checker.check("a.rb", "# frozen_string_literal: true\nputs 1\n").map(&:rule)
  end
end
