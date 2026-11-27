# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "open3"
require "rbconfig"

class TestBootBanner < Minitest::Test
  def test_print_is_silent_by_default
    ENV.delete("MASTER_BOOT_STATUS")
    io = StringIO.new
    Master::CLI::BootBanner.print(io:)
    assert_empty io.string
  end

  def test_print_emits_banner_lines_when_enabled
    ENV["MASTER_BOOT_STATUS"] = "1"
    io = StringIO.new
    Master::CLI::BootBanner.print(io:)
    assert_includes io.string, "boot0 at mainbus0: safe "
    assert_includes io.string, "master0: ready"
  ensure
    ENV.delete("MASTER_BOOT_STATUS")
  end

  def test_banner_lines_use_dmesg_unit_grammar
    lines = Master::CLI::BootBanner.banner_lines

    assert(lines.all? { |line| line.match?(/\A(?:[a-z]+\d+ at [a-z]+\d+: |[a-z]+\d+: )/) }, lines.inspect)
  end

  def test_banner_lines_reflect_env_flags
    lines = Master::CLI::BootBanner.banner_lines
    assert(lines.any? { |line| line.start_with?("boot0 at mainbus0: safe ") })
    assert(lines.any? { |line| line.start_with?("style0 at master0: ") })
  end

  # Regression: bin/cli's --boot-status flag set MASTER_BOOT_STATUS=1 but
  # nothing ever printed the banner, so the flag was completely inert. Its
  # units now attach inside the splash, in the device tree before "root on",
  # and the splash's "root on" is the only line that says the boot is done.
  def test_boot_status_units_attach_before_root_on
    lines = boot_status_splash
    boot = lines.index { |line| line.start_with?("boot0 at mainbus0: safe ") }
    root = lines.index { |line| line.start_with?("root on master0") }

    assert boot && root && boot < root, lines.inspect
    assert lines.first.start_with?("master0 at mainbus0: MASTER "), lines.first
    refute_includes lines, "master0: ready"
  end

  # As in the kernel, a unit attaches once and reports after as "unit: detail".
  def test_boot_status_splash_attaches_each_unit_once
    attached = boot_status_splash.filter_map { |line| line[/\A([a-z]+\d+) at /, 1] }

    assert_equal attached.uniq, attached
  end

  private

  def boot_status_splash
    ENV["MASTER_BOOT_STATUS"] = "1"
    Master::Voice::Renderer.new(config: {}).splash("grok-cli:opus").lines(chomp: true)
  ensure
    ENV.delete("MASTER_BOOT_STATUS")
  end

  public

  def test_boot_has_no_ascii_wordmark_before_the_dmesg_lines
    source = File.read(File.join(Master::ROOT, "lib", "boot", "master_boot.rb"))
    refute_includes source, "CLI::BootBanner.wordmark"
    refute_respond_to Master::CLI::BootBanner, :wordmark
  end

  # `bin/master --help` prints usage without building the runtime. The option
  # parser ran only after Master.boot, so help cost a full boot and exited 1
  # whenever that boot raised. The banner prints on the way into the boot, so
  # its absence proves help returned first, whether or not a boot would succeed.
  def test_cli_help_returns_before_the_boot_banner
    master = File.join(Master::ROOT, "bin", "master")
    out, status = Open3.capture2e({ "MASTER_BOOT_STATUS" => "1" }, RbConfig.ruby, master, "--help",
                                  chdir: Master::ROOT, stdin_data: "")
    assert status.success?, "bin/master --help exited #{status.exitstatus}: #{out.lines.last(3).join}"
    assert_includes out, "Usage: bin/master"
    refute_includes out, "boot0 at mainbus0: safe", "bin/master --help started the boot"
  end

  # The Claude Code print-mode flags are parsed before the boot, so help can list
  # them and a permission mode can warn without building the runtime.
  def test_cli_help_lists_the_print_mode_flags
    master = File.join(Master::ROOT, "bin", "master")
    out, status = Open3.capture2e(RbConfig.ruby, master, "--permission-mode", "bypassPermissions", "--help",
                                  chdir: Master::ROOT, stdin_data: "")
    assert status.success?, "bin/master --help exited #{status.exitstatus}: #{out.lines.last(3).join}"
    %w[--model --output-format --permission-mode --allowedTools].each { |flag| assert_includes out, flag }
    assert_includes out, "bypasses nothing"
  end
end

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class TestBootChecks < Minitest::Test
  CHECKS = Master::Ground::BootChecks

  def with_root
    Dir.mktmpdir("master-boot-checks-") do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      yield root
    end
  end

  def test_invalid_config_remains_fatal_and_aborts
    with_root do |root|
      File.write(File.join(root, ".master", "config.yml"), "web_port: 0\n")

      result = CHECKS.send(:check_config_valid, root)
      refute result.ok
      assert_equal :fatal, result.severity
      assert_includes result.message, "web_port must be 1-65535"

      assert_raises(SystemExit) { CHECKS.abort_on_fatals([result]) }
    end
  end

  def test_missing_data_file_remains_fatal
    with_root do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      File.write(File.join(data, "soul.yml"), "---\n")
      File.write(File.join(data, "laws.yml"), "---\n")
      result = CHECKS.send(:check_data_dir, root)

      refute result.ok
      assert_equal :fatal, result.severity
      assert_includes result.message, "budgets.yml"
    end
  end
end

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/boot/entrypoint"

class TestBootEntrypoint < Minitest::Test
  SOURCE = File.read(File.expand_path("../lib/boot/entrypoint.rb", __dir__))
  GEMFILE = File.read(File.expand_path("../Gemfile", __dir__))
  LOCKFILE = File.read(File.expand_path("../Gemfile.lock", __dir__))

  def test_ci_compatibility_entrypoint_delegates_boot_to_bin_check_once
    source = File.read(File.expand_path("../bin/ci", __dir__))

    refute_includes source, "Boot::Entrypoint.prepare!"
    assert_match(/exec\(RbConfig\.ruby, File\.join\(__dir__, "check"\), "--profile=ci"/, source)
  end

  def test_check_defers_default_gems_until_bundle_activation
    source = File.read(File.expand_path("../bin/check", __dir__))
    boot = source.index("Master::Boot::Entrypoint.prepare!")
    refute_nil boot
    %w[shellwords open3 timeout].each do |name|
      position = source.index(%(require "#{name}"))
      refute_nil position
      assert_operator position, :>, boot, "#{name} must load from the locked bundle"
    end
  end

  def test_json_uses_the_bundle_resolution_not_a_ruby_release_pin
    refute GEMFILE.lines.any? { |line| line.start_with?('gem "json", "=') }
    refute LOCKFILE.lines.any? { |line| line.start_with?("  json (=") }
    assert LOCKFILE.lines.any? { |line| line.start_with?("    json (") }
  end

  def test_json_is_loaded_only_after_bundler_activation
    bundle_index = SOURCE.index("activate_bundle!(root)")
    json_index = SOURCE.index('require "json"')
    refute_nil bundle_index
    refute_nil json_index
    assert_operator json_index, :>, bundle_index
  end

  def test_lockfile_bundler_version_is_read_from_the_master_lock
    Dir.mktmpdir("master-entrypoint") do |root|
      File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
        GEM
          remote: https://rubygems.org/

        DEPENDENCIES

        BUNDLED WITH
          4.0.7
      LOCK

      reader = Master::Boot::Entrypoint.method(:locked_bundler_version)
      assert_equal "4.0.7", reader.call(root)
    end
  end

  def test_supported_ruby_floor_has_no_artificial_upper_bound
    env = Operator::Environment

    %w[3.3.0 3.3.8 3.4.9 4.0.5 4.0.7 4.1.0 4.2.0].each do |version|
      assert env::SUPPORTED_RUBY_MIN <= Gem::Version.new(version), version
    end
    # The Gemfile ("ruby >= 3.2"), the gemspec's required_ruby_version and
    # bin/ruby's MIN_MINOR now gates on 3.2, so the floor is 3.2; 3.1 stays
    # below it.
    assert env::SUPPORTED_RUBY_MIN <= Gem::Version.new("3.2.0")
    refute env::SUPPORTED_RUBY_MIN <= Gem::Version.new("3.1.9")
  end

  def test_inline_program_does_not_reexec_when_the_selected_ruby_version_matches
    candidate = { path: "/different/path/to/ruby", version: Gem::Version.new(RUBY_VERSION) }
    root = File.expand_path("../..", __dir__)

    Operator::RubyRunner.stub(:best_available_ruby, candidate) do
      Master::Boot::Entrypoint.stub(:same_file?, false) do
        assert_nil Master::Boot::Entrypoint.reexec_best_ruby!(
          root:, env: {}, out: StringIO.new, argv: ["-e", "puts :ok"], program: "-e",
        )
      end
    end
  end

  def test_preloaded_wrong_bundler_reexecs_into_a_clean_process
    Dir.mktmpdir("master-entrypoint") do |root|
      program = write_boot_script(root, "bin", "master", executable: true)
      env = {
        "RUBYOPT" => "-rbundler/setup",
        "RUBYLIB" => "/wrong/bundler/lib",
        "BUNDLE_GEMFILE" => "/wrong/Gemfile",
        "BUNDLE_LOCKFILE" => "/wrong/Gemfile.lock",
      }

      clean, rest, options = capture_reexec(root:, env:, program:)

      assert_equal [program, "--fast"], rest
      assert_equal({ unsetenv_others: true }, options)
      assert_equal "1", clean["MASTER_BUNDLER_REEXEC_DONE"]
      refute clean.key?("RUBYOPT")
      refute clean.key?("RUBYLIB")
      refute clean.key?("BUNDLE_GEMFILE")
      refute clean.key?("BUNDLE_LOCKFILE")
    end
  end

  def test_reexec_of_a_non_executable_script_prefixes_the_interpreter
    Dir.mktmpdir("master-entrypoint") do |root|
      # `ruby tools/x.rb` leaves no executable bit; a bare exec would EACCES.
      program = write_boot_script(root, "tools", "boot_smoke.rb", executable: false)

      _clean, rest, _options = capture_reexec(root:, env: {}, program:)

      assert_equal [RbConfig.ruby, program, "--fast"], rest
    end
  end

  def test_boot_receipt_is_private_under_a_shared_umask
    Dir.mktmpdir("master-entrypoint") do |root|
      old_umask = File.umask(0o002)
      begin
        Master::Boot::Entrypoint.send(:write_boot_receipt!, root:, out: StringIO.new)
      ensure
        File.umask(old_umask)
      end

      dir = File.join(root, ".master")
      assert_equal "700", format("%03o", File.stat(dir).mode & 0o777)
      assert_equal "600", format("%03o", File.stat(File.join(dir, "boot.json")).mode & 0o777)
    end
  end

  # rc.d/master shares MASTER/.master with the daemon's group so it can create
  # its TTS sockets; a dev boot clamping it to 0700 locked the daemon out.
  def test_boot_receipt_clears_other_but_keeps_the_shared_group
    Dir.mktmpdir("master-entrypoint") do |root|
      dir = File.join(root, ".master")
      FileUtils.mkdir_p(dir)
      File.chmod(0o775, dir)

      Master::Boot::Entrypoint.send(:write_boot_receipt!, root:, out: StringIO.new)

      assert_equal "770", format("%03o", File.stat(dir).mode & 0o777)
      assert_equal "600", format("%03o", File.stat(File.join(dir, "boot.json")).mode & 0o777)
    end
  end

  private

  # A scratch checkout with the lock reexec_mismatched_bundler! reads, and the
  # program it would re-exec, executable or not.
  def write_boot_script(root, *segments, executable:)
    File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/

      DEPENDENCIES

      BUNDLED WITH
        4.0.5
    LOCK
    program = File.join(root, *segments)
    FileUtils.mkdir_p(File.dirname(program))
    File.write(program, executable ? "#!/usr/bin/env ruby\n" : "puts :ok\n")
    File.chmod(executable ? 0o755 : 0o644, program)
    program
  end

  # [clean_env, argv, options] from the re-exec, with exec and Bundler's active
  # version stubbed so no process is replaced.
  def capture_reexec(root:, env:, program:)
    active = Struct.new(:version).new(Gem::Version.new("4.0.7"))
    captured = nil

    Master::Boot::Entrypoint.stub(:exec, ->(clean, *rest, **options) { captured = [clean, rest, options] }) do
      Gem.stub(:loaded_specs, { "bundler" => active }) do
        Master::Boot::Entrypoint.reexec_mismatched_bundler!(
          root:, env:, out: StringIO.new, argv: ["--fast"], program:,
        )
      end
    end

    refute_nil captured
    captured
  end
end

require_relative "test_helper"
require "open3"
require "rbconfig"

# boot/entrypoint.rb activates the lockfile's pinned default gems (json, date)
# before `require "time"` loads date. On vm23 (Ruby 3.4) the default date is
# older than the lock's, and Bundler.setup died on "already activated date
# 3.4.1" until the pin ran first (2026-10-12, tts-worker --selftest).
#
# Complementarily, `require "time"` itself must run only after bundler/setup:
# on a fresh checkout the retry pin cannot see the just-installed store, so
# loading time before setup activated the interpreter's default date and
# Bundler.setup crashed with the same "already activated date" error
# (2026-11-18, self-test boot on a Ruby 3.4.6 sandbox).
class TestBootEntrypointPins < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENTRYPOINT = File.join(ROOT, "lib", "boot", "entrypoint.rb")

  def locked(name)
    File.read(File.join(ROOT, "Gemfile.lock"), encoding: "UTF-8")[/^    #{name} \(([\d.]+)\)$/, 1]
  end

  def test_the_locked_default_gems_are_the_ones_active_after_the_entrypoint_loads
    %w[json date].each do |name|
      pin = locked(name)
      next unless pin && Gem::Specification.find_all_by_name(name, pin).any?

      out, status = Open3.capture2e(RbConfig.ruby, "-e", "require #{ENTRYPOINT.inspect}; print Gem.loaded_specs[#{name.inspect}]&.version")
      assert_predicate status, :success?, out
      assert_equal pin, out.strip, "#{name} must be on the locked version before Bundler.setup"
    end
  end

  def test_time_is_required_only_after_bundler_setup
    source = File.read(ENTRYPOINT, encoding: "UTF-8")
    setup_at = source.index('require "bundler/setup"')
    time_at = source.index('require "time"')

    refute_nil setup_at, "activate_bundle! must require bundler/setup"
    refute_nil time_at, "time/date must still be loaded by the entrypoint"
    assert_operator setup_at, :<, time_at,
      'require "time" must come after require "bundler/setup" so the locked ' \
      "date is active before time.rb loads it; loading time first activates " \
      "the interpreter's default date and crashes Bundler.setup on a fresh checkout"
  end
end

require_relative "test_helper"
require_relative "support_fake_config"

# A model the operator saved leads every chain, including the ones a one-shot
# instruction or a /fix pass builds. Only Session#run used to apply the pin, so
# the saved model never reached those runs.
class TestBootModelPin < Minitest::Test
  class FakeRouter
    attr_reader :probes, :waits

    def initialize(reachable:, pending: false)
      @reachable = reachable
      @pending = pending
      @probes = 0
      @waits = []
    end

    def constrained_for(operation:) = "agy:gemini-3.8-flash-medium"

    def unreachable_reason(_model, wait: false)
      @probes += 1
      @waits << wait
      return "checking provider sign-in" if @pending

      @reachable ? nil : "down"
    end
  end

  class FakeAgent
    include Master::Review::Agent::ModelOverride
    include Master::Review::Agent::ModelSelector

    def initialize(saved:, router:)
      @config = Master::TestSupport::FakeConfig.new(model: saved)
      @model_router = router
      @bus = nil
    end

    attr_writer :chain

    def routed_chain(_message, task_type:) = @chain || %w[free/a free/b]
    def model = "free/a"
    attr_writer :local_only

    def local_only? = @local_only == true
    public :routed_models, :model_for
  end

  LANE_RANK = { local: 4, paid_tail: 1, free: 2 }.freeze

  def test_homeostat_cheap_bias_does_not_break_the_fallback_ladder
    chain = ["grok-cli:sonnet", "openrouter/free-model:free", "web-chat:grok", "ollama:gemma3:4b"]
    router = tiered_router(chain)
    homeostat = Struct.new(:model_tier_bias).new(:cheap)

    assert_equal chain, selector_probe(router:, homeostat:).routed_chain(nil, task_type: :exploration)
  end

  def test_a_saved_model_leads_the_chain_without_the_session
    agent = FakeAgent.new(saved: "grok-cli:sonnet", router: FakeRouter.new(reachable: true))

    assert_equal %w[grok-cli:sonnet free/a free/b], agent.routed_models
  end

  def test_an_unreachable_saved_model_leaves_the_pool_order_alone
    agent = FakeAgent.new(saved: "grok-cli:sonnet", router: FakeRouter.new(reachable: false))

    assert_equal %w[free/a free/b], agent.routed_models
  end

  def test_boot_model_pin_never_waits_for_an_unfinished_provider_probe
    router = FakeRouter.new(reachable: true, pending: true)
    agent = FakeAgent.new(saved: "grok-cli:sonnet", router:)

    agent.pin_boot_model!

    assert_equal "grok-cli:sonnet", agent.instance_variable_get(:@preferred_model)
    assert_equal [false], router.waits
  end

  # ask(..., operation:) takes this path, which is the one /fix's semantic laws and
  # the council use. A saved model is a preference, not a pin: availability and the
  # operation's own constraint choose the lane, so a saved sonnet never forces every
  # /fix call onto sonnet.
  def test_an_operation_call_is_chosen_by_availability_not_the_saved_model
    agent = FakeAgent.new(saved: "grok-cli:sonnet", router: FakeRouter.new(reachable: true))

    assert_equal "agy:gemini-3.8-flash-medium", agent.model_for(operation: :semantic_law)
  end

  def test_an_explicit_model_choice_pins_the_operation_call
    agent = FakeAgent.new(saved: "grok-cli:sonnet", router: FakeRouter.new(reachable: true))
    agent.model = "grok-cli:opus"

    assert_equal "grok-cli:opus", agent.model_for(operation: :semantic_law)
  end

  def test_a_saved_free_model_never_leads_a_live_subscription_chain
    agent = FakeAgent.new(saved: "nvidia/nemotron-3-ultra-550b-a55b:free", router: FakeRouter.new(reachable: true))
    agent.chain = %w[grok-cli:opus deepseek-chat]

    assert_equal %w[grok-cli:opus deepseek-chat], agent.routed_models
  end

  def test_a_saved_cloud_model_is_never_pinned_in_local_only_mode
    agent = FakeAgent.new(saved: "grok-cli:sonnet", router: FakeRouter.new(reachable: true))
    agent.local_only = true

    assert_equal %w[free/a free/b], agent.routed_models
    assert_equal "agy:gemini-3.8-flash-medium", agent.model_for(operation: :semantic_law)
  end

  def test_the_reachability_probe_runs_once_per_agent
    router = FakeRouter.new(reachable: false)
    agent = FakeAgent.new(saved: "grok-cli:sonnet", router:)
    3.times { agent.routed_models }

    assert_equal 1, router.probes
  end

  class RouteFailureProbe
    include Master::Review::Agent::ModelSelector

    def initialize(router:, model:)
      @model_router = router
      @config = Struct.new(:model, :task_type).new(model, :exploration)
      @homeostat = nil
      @bus = nil
    end

    public :routed_chain
  end

  def test_router_exception_retains_the_independent_fallback_ladder
    router = Object.new
    router.define_singleton_method(:fallback_chain) do |task_type:|
      raise IOError, "router cache unavailable for #{task_type}"
    end
    probe = RouteFailureProbe.new(router:, model: "configured/last-resort")
    catalogue = %w[paid/primary local/secondary free/final]

    chain = Master::Io::LaneSelection.stub(:explicit_models, catalogue) do
      Master::Io::LaneSelection.stub(:order_or_all, ->(models) { models.reverse }) do
        probe.routed_chain(nil, task_type: :exploration)
      end
    end

    assert_equal %w[free/final local/secondary paid/primary configured/last-resort], chain
  end

  def test_prompt_and_model_status_read_the_promoted_runtime_lane
    router = Struct.new(:reachable) do
      def unreachable_reason(_model, wait: false) = reachable ? nil : "provider unavailable"
    end.new(true)
    agent = Object.new
    agent.extend(Master::Review::Agent::ModelOverride)
    agent.instance_variable_set(:@runtime_model, "grok-cli:auto")
    agent.instance_variable_set(:@model_router, router)
    agent.instance_variable_set(:@bus, nil)
    agent.define_singleton_method(:routed_models) { ["grok-cli:opus"] }

    assert_equal "grok-cli:auto", agent.model
    status = Master::CLI::CommandRegistry.dispatch_model(
      agent:, config: { "model" => "saved-default" }, metrics: nil, root: Master::ROOT, arg: "status"
    )
    assert_includes status, "model: grok-cli:auto"
    state = Master::Voice::Renderer.new(config: {}).state_line(agent.model)
    assert_includes state, "grok-cli:auto"

    router.reachable = false
    assert_equal "grok-cli:opus", agent.model
    assert_nil agent.instance_variable_get(:@runtime_model)
  end

  def test_empty_router_ladder_uses_the_independent_fallback_catalogue
    router = Object.new
    router.define_singleton_method(:fallback_chain) { |task_type:| [] }
    router.define_singleton_method(:priority_fallback_order) { |models, task_type:| models }
    probe = RouteFailureProbe.new(router:, model: "configured/last-resort")
    catalogue = %w[paid/primary local/secondary free/final]

    chain = Master::Io::LaneSelection.stub(:explicit_models, catalogue) do
      Master::Io::LaneSelection.stub(:order_or_all, ->(models) { models.reverse }) do
        probe.routed_chain(nil, task_type: :exploration)
      end
    end

    assert_equal %w[free/final local/secondary paid/primary configured/last-resort], chain
  end

  private

  def tiered_router(chain)
    router = Master::CLI::Routing::ModelRouter.allocate
    router.instance_variable_set(:@rules, { "openai_compatible" => {} })
    cheap = %w[openrouter/free-model:free ollama:gemma3:4b]
    rank = ->(model) { model.start_with?("web-chat:") ? 3 : LANE_RANK.fetch(Master::Io::LaneSelection.kind(model), 0) }
    router.define_singleton_method(:fallback_chain) { |task_type:| chain }
    router.define_singleton_method(:tier_for_model) { |model| cheap.include?(model) ? "cheap" : "strong" }
    router.define_singleton_method(:priority_fallback_order) do |models, task_type: :exploration|
      models.each_with_index.sort_by { |model, index| [rank.call(model), index] }.map(&:first)
    end

    router
  end

  def selector_probe(router:, homeostat:)
    probe_class = Class.new do
      include Master::Review::Agent::ModelSelector

      def initialize(router:, homeostat:)
        @model_router = router
        @homeostat = homeostat
        @config = Master::TestSupport::FakeConfig.new(model: "grok-cli:sonnet")
      end

      public :routed_chain
    end

    probe_class.new(router:, homeostat:)
  end
end

require_relative "test_helper"
require_relative "../lib/ground/service_supervisor"

class TestBootNamespaces < Minitest::Test
  def test_service_supervisor_uses_the_absolute_io_namespace
    assert_includes Master::Ground::ServiceSupervisor.ancestors, Master::Io::AtomicWrite
  end

  def test_model_quota_loads_through_the_master_io_namespace
    require_relative "../lib/io/model_quota"
    assert defined?(Master::Io::ModelQuota)
    assert Master::Io::ModelQuota.respond_to?(:snapshot)
  end
end

require "minitest/autorun"
require "master"
require_relative "../lib/cli/boot_banner"

class BootSecurityLinesTest < Minitest::Test
  def test_boot_describes_real_security_layers
    lines = Master::CLI::BootBanner.security_lines
    assert_match(/\Asecurity0 at master0: .*\badmission\b/, lines.first)
    # pledge is claimed only on OpenBSD; elsewhere the unit says it is not configured.
    pledge = Master::Ground::Pledge.openbsd? ? "staged reduction" : "not configured"
    assert_includes lines, "pledge0 at security0: #{pledge}"
    assert_includes lines.join("\n"), "transaction-backed self-change"
    assert_includes lines.join("\n"), "proposal-only"
  end
end
