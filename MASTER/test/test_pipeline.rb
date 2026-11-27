# frozen_string_literal: true

require_relative "test_helper"

# Pipeline unit tests — Result-monadic chaining and deploy-check contract.
class TestPipeline < Minitest::Test
  include Master

  class OkStage
    def call(ctx) = Master::Result.ok(ctx.merge(output: "ok"))
  end

  class ErrStage
    def initialize(cat = :unknown) = (@cat = cat)
    def call(_ctx) = Master::Result.err("boom", category: @cat)
  end

  # Records what reached it, so a short circuit can be seen from the far side.
  class RecordStage
    attr_reader :calls

    def initialize = @calls = []
    def call(ctx) = (@calls << ctx[:user_message]; Master::Result.ok(ctx))
  end

  class RaiseStage
    def call(_ctx) = raise "stage exploded"
  end

  class AddStage
    def initialize(key, value)
      @key = key
      @value = value
    end

    def call(ctx) = Master::Result.ok(ctx.merge(@key => @value))
  end

  FakeRule = Struct.new(:id, :auto_fix)

  class FakeScanner
    attr_reader :rules

    def initialize(findings)
      @findings = findings
      @rules = [FakeRule.new("SELF_RULE", false)]
    end

    def scan_dir(path, depth:, stream: false, laws: nil)
      Master::Result.ok([[File.join(path, "example.rb"), Master::Result.ok(@findings)]])
    end
  end

  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  def test_colour_patch_stays_plain_when_terminal_palette_is_unavailable
    pass = Master::CLI::Pipeline::Pass.allocate
    original_stdout = $stdout
    terminal = Object.new
    def terminal.tty? = true
    $stdout = terminal

    assert_equal "+added\n", pass.send(:colour_patch, "+added\n")
  ensure
    $stdout = original_stdout
  end

  def test_happy_path_passes_context_through
    pipe = Master::CLI::Pipeline.new([OkStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok(user_message: "hi"))
    assert result.ok?
    assert_equal "ok", result.value![:output]
  end

  def test_call_accepts_already_wrapped_pipeline_context
    pipe = Master::CLI::Pipeline.new([OkStage.new])
    ctx = Master::CLI::PipelineContext.build(user_message: "hi")

    result = pipe.call(ctx)

    assert result.ok?
    assert_equal "ok", result.value![:output]
  end

  def test_pipeline_complete_event_publishes_timings
    bus = FakeBus.new
    pipe = Master::CLI::Pipeline.new([OkStage.new], bus:)

    result = pipe.call(Master::Result.ok(user_message: "hi"))

    assert result.ok?
    event = bus.events.find { |name, _payload| name == "pipeline:complete" }
    assert event
    assert_equal true, event.last[:success]
    assert_includes event.last[:timings].keys, "OkStage"
  end

  def test_pipeline_context_caps_large_output_on_merge
    ctx = Master::CLI::PipelineContext.build(user_message: "hi")
    merged = ctx.merge(output: "x" * 10_000)

    assert_equal Master::CLI::PipelineContext::MAX_OUTPUT_BYTES, merged[:output].bytesize
  end

  def test_pipeline_context_inspect_never_discloses_prompt_output_or_tool_data
    ctx = Master::CLI::PipelineContext.build(
      user_message: "prompt-private-marker",
      output: "provider-private-marker",
      metadata: { access_token: "token-private-marker" },
      tool_calls: [{ arguments: "argument-private-marker" }],
    )

    inspected = ctx.inspect

    %w[user_message output metadata tool_calls].each { |key| assert_includes inspected, key }
    %w[prompt-private-marker provider-private-marker token-private-marker argument-private-marker].each do |secret|
      refute_includes inspected, secret
    end
  end

  def test_pipeline_context_caps_timing_entries_on_merge
    ctx = Master::CLI::PipelineContext.build(user_message: "hi")
    timings = 25.times.to_h { |i| ["stage#{i}", i] }
    merged = ctx.merge(_timings: timings)

    assert_equal Master::CLI::PipelineContext::MAX_TIMINGS, merged[:_timings].size
    refute_includes merged[:_timings].keys, "stage0"
    assert_includes merged[:_timings].keys, "stage24"
  end

  def test_first_error_short_circuits
    after = RecordStage.new
    pipe = Master::CLI::Pipeline.new([OkStage.new, ErrStage.new, after])
    result = pipe.call(Master::Result.ok(user_message: "hi"))
    refute result.ok?
    assert_equal "boom", result.message
    assert_empty after.calls, "a stage after the error still ran"
  end

  def test_intake_parses_a_slash_command
    result = Master::CLI::Pipeline.new([Master::CLI::Stages::Intake.new])
                                   .call(Master::CLI::PipelineContext.build(user_message: "/fix lib/"))

    assert result.ok?, result.inspect
    assert_equal :command, result.value![:intent]
    assert_equal "fix", result.value![:command]
    assert_equal "lib/", result.value![:args]
  end

  def test_intake_reads_plain_text_as_an_llm_turn_and_hands_it_on
    recorder = RecordStage.new
    result = Master::CLI::Pipeline.new([Master::CLI::Stages::Intake.new, recorder])
                                   .call(Master::CLI::PipelineContext.build(user_message: "what is fix_loop for?"))

    assert result.ok?, result.inspect
    assert_equal :llm, result.value![:intent]
    assert_equal ["what is fix_loop for?"], recorder.calls
  end

  def test_intake_expands_only_files_inside_its_configured_root
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "notes.txt"), "inside-only\n")
      result = Master::CLI::Stages::Intake.new(root: dir).call(
        Master::CLI::PipelineContext.build(user_message: "summarise @notes.txt"),
      )

      assert result.ok?, result.inspect
      assert_includes result.value![:message], "inside-only"
    end
  end

  def test_intake_does_not_expand_a_reference_outside_its_configured_root
    Dir.mktmpdir do |dir|
      outside = File.join(File.dirname(dir), "intake-outside-#{Process.pid}.txt")
      File.write(outside, "outside-secret\n")
      result = Master::CLI::Stages::Intake.new(root: dir).call(
        Master::CLI::PipelineContext.build(user_message: "read @../#{File.basename(outside)}"),
      )

      assert result.ok?, result.inspect
      refute_includes result.value![:message], "outside-secret"
    ensure
      File.delete(outside) if outside && File.exist?(outside)
    end
  end

  def test_intake_does_not_expand_a_symlink_to_a_secret_file
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "API_KEY=inside-secret\n")
      File.symlink(".env", File.join(dir, "notes.txt"))
      result = Master::CLI::Stages::Intake.new(root: dir).call(
        Master::CLI::PipelineContext.build(user_message: "read @notes.txt"),
      )

      assert result.ok?, result.inspect
      refute_includes result.value![:message], "inside-secret"
    end
  end

  def test_fix_claims_the_vm23_control_plane_slot
    probe = Object.new
    seen = nil
    probe.define_singleton_method(:run) do |_target, requested: false|
      seen = Master::Ops::LoopOwner.active
      # The loop speaks in terminal states; a bare :done reads as incomplete.
      Master::Result.ok("DONE: clean")
    end
    probe.define_singleton_method(:terminal_receipt_summary) do
      "fix-receipt0: done run=fixture target=MASTER result=ok changed=1 assessment=verified ledger=4 sha256=#{"a" * 64}"
    end

    pass = Master::CLI::Pipeline::Pass.allocate
    pass.instance_variable_set(:@fix_loop, probe)
    pass.instance_variable_set(:@failed_stages, [])
    pass.instance_variable_set(:@bus, nil)
    # run_fix reads HEAD before and after to count what the loop delivered.
    checkout = Master::Io::GitOperations.new(Master::ROOT)
    pass.define_singleton_method(:git) { checkout }

    result = pass.send(:run_fix, File.expand_path("../tmp", __dir__))

    assert_includes result, "DONE: clean"
    assert_includes result, "fix-receipt0: done run=fixture"
    assert_match(/DONE: clean\n\nfix-receipt0: done run=fixture/, result)
    assert_equal "fix", seen.fetch("loop")
    assert_nil Master::Ops::LoopOwner.active
  ensure
    Master::Ops::LoopOwner.release
  end

  def test_write_pass_leaves_observation_to_the_repair_lifecycle
    pass = Master::CLI::Pipeline::Pass.allocate
    loop_stub = Object.new
    loop_stub.define_singleton_method(:owns_observation?) { true }
    pass.instance_variable_set(:@fix_loop, loop_stub)
    pass.instance_variable_set(:@apply, true)
    pass.define_singleton_method(:proof_baseline) { |_| :baseline }
    pass.define_singleton_method(:repo_git) { Struct.new(:changed_paths).new([]) }
    pass.define_singleton_method(:git) { Struct.new(:head).new("before") }
    pass.define_singleton_method(:log_phase) { |*, &block| block.call }
    pass.define_singleton_method(:run_fix) { |_| "DONE: clean" }
    pass.define_singleton_method(:changes_section) { |_| "verified change" }
    pass.define_singleton_method(:repair_unproven) { |_| nil }
    pass.define_singleton_method(:nothing_delivered?) { |_| false }
    pass.define_singleton_method(:proof_section) { |_, baseline| ["proof", baseline] }
    pass.define_singleton_method(:put_back_autofix) {}
    forbidden = ->(**) { flunk "duplicate observation" }
    pass.stub(:observe_section, forbidden) do
      pass.stub(:reobserve_section, forbidden) do
        sections = pass.send(:fix_sections, resolved: "RAILS", shell: "RAILS", posture: {}, aesthetic: true, critique: false)
        assert_equal %w[observe repair changes re-observe proof], sections.map(&:first)
        assert_equal ["proof", :baseline], sections.last
      end
    end
  end

  def test_fix_loop_receives_the_same_validated_task_contract_in_keyword_and_thread_scope
    contract = Master::Fix::TaskContract.build(
      intent: "functional_change",
      scope: ["MASTER/lib/cli/**"],
      preserve: [],
      proof: ["focused_tests"],
    )
    seen = nil
    probe = Object.new
    probe.define_singleton_method(:run) do |_target, requested:, task_contract:|
      seen = [task_contract, Master::Fix::TaskContract.current]
      Master::Result.ok("DONE: clean")
    end
    pass = Master::CLI::Pipeline::Pass.allocate
    pass.instance_variable_set(:@fix_loop, probe)
    pass.instance_variable_set(:@cancellation, nil)
    pass.instance_variable_set(:@task_contract, contract)

    pass.send(:run_fix_loop, File.join(Master::REPO_ROOT, "MASTER"))

    assert_equal [contract, contract], seen
    assert_nil Master::Fix::TaskContract.current
  end

  def test_task_contract_scope_is_repository_relative_and_target_bounded
    pass = Master::CLI::Pipeline::Pass.new(
      scanner: nil,
      fix_loop: Object.new,
      root: Master::ROOT,
      task_intent: "content_only",
    )

    contract = pass.send(:build_task_contract, File.join(Master::ROOT, "lib", "cli"))

    assert_equal "content_only", contract.intent
    assert_equal ["MASTER/lib/cli/**"], contract.scope
    assert_includes contract.preserve, "visual_identity"
    assert_includes contract.proof, "focused_tests"
  end

  def test_whole_checkout_task_contract_names_only_the_governed_trees
    pass = Master::CLI::Pipeline::Pass.new(scanner: nil, fix_loop: Object.new, root: Master::ROOT)
    contract = pass.send(:build_task_contract, Master::REPO_ROOT)

    # BIZ joined the registry in 734dcaa4; the scope follows MasterPaths::TREES
    # rather than a second copy of the list, so this reads it from there. The
    # contract sorts its scope, so the order is not the registry's.
    assert_equal MasterPaths::TREES.map { |tree| "#{tree}/**" }.sort, contract.scope
  end

  def test_fix_phase_timings_are_accumulated_for_structured_reporting
    pass = Master::CLI::Pipeline::Pass.allocate
    pass.instance_variable_set(:@unit, "review0")
    pass.instance_variable_set(:@stage_timings, Hash.new(0.0))
    result = nil

    Master::Trace::Dmesg.stub(:attach, ->(*) {}) do
      result = pass.send(:log_phase, "scan0", "observe", nil) { :scanned }
    end

    assert_equal :scanned, result
    timings = pass.instance_variable_get(:@stage_timings)
    assert_includes timings, "observe"
    assert_operator timings.fetch("observe"), :>=, 0.0
  end

  def test_fix_writes_by_default_with_a_named_target
    registry = Master::CLI::CommandRegistry

    assert registry.writes_requested?(apply: true, only: nil)
    refute registry.writes_requested?(apply: false, only: nil)
    refute registry.writes_requested?(apply: true, only: "critique")
    assert registry.writes_requested?(apply: true, only: nil)
  end

  def test_mutating_fix_requires_a_named_target
    registry = Master::CLI::CommandRegistry

    missing_target = registry.send(:fix_dispatch_options, "--apply", nil)
    authorized = registry.send(:fix_dispatch_options, "MASTER", nil)

    assert_match(/named repository target/, missing_target.fetch(:mode_error))
    assert_nil authorized[:mode_error]
    assert_equal "repair", authorized.fetch(:mode)
    assert_equal "MASTER", authorized.fetch(:target)
    assert_equal true, authorized.fetch(:apply)

    host_read = registry.send(:fix_dispatch_options, "--host-evidence OPENBSD", nil)
    assert_nil host_read[:mode_error]
    assert_equal true, host_read.fetch(:host_evidence)
    assert_includes host_read.fetch(:raw), "--host-evidence"
    assert_equal "OPENBSD", host_read.fetch(:target)
    assert registry.writes_requested?(apply: host_read.fetch(:apply), only: host_read.fetch(:only))

    host_write = registry.send(:fix_dispatch_options, "--mode=repair --apply OPENBSD --host-evidence", nil)
    assert_nil host_write[:mode_error]
    assert_equal true, host_write.fetch(:host_evidence)
    assert registry.writes_requested?(apply: host_write.fetch(:apply), only: host_write.fetch(:only))

    refused_host = registry.send(:fix_dispatch_options, "--host-evidence MASTER", nil)
    assert_match(/exact OPENBSD target/, refused_host.fetch(:mode_error))
  end

  def test_unnamed_fix_is_preview_unless_explicit_apply_demands_a_target
    registry = Master::CLI::CommandRegistry

    ["", "--mode=all", "--trace"].each do |raw|
      options = registry.send(:fix_dispatch_options, raw, nil)
      assert_nil options[:mode_error], raw
      refute registry.writes_requested?(apply: options.fetch(:apply), only: options.fetch(:only)), raw
    end
    assert_match(/named repository target/, registry.send(:fix_dispatch_options, "--apply", nil).fetch(:mode_error))
  end

  def test_audit_and_visual_modes_remain_read_only_even_with_apply
    registry = Master::CLI::CommandRegistry

    %w[audit visual].each do |mode|
      options = registry.send(:fix_dispatch_options, "--mode=#{mode} --apply MASTER", nil)
      refute options.fetch(:apply), "#{mode} must never mutate"
      refute registry.writes_requested?(apply: options.fetch(:apply), only: options.fetch(:only))
    end
  end

  def test_intake_rejects_an_empty_message
    result = Master::CLI::Pipeline.new([Master::CLI::Stages::Intake.new])
                                   .call(Master::CLI::PipelineContext.build(user_message: "   "))

    refute result.ok?
    assert_match(/empty/, result.message)
  end

  def test_raise_in_stage_becomes_err
    pipe = Master::CLI::Pipeline.new([OkStage.new, RaiseStage.new])
    result = pipe.call(Master::Result.ok(user_message: "hi"))
    refute result.ok?
    assert_match(/exploded/, result.message)
  end

  def test_pipeline_error_does_not_mutate_outside_git_workspace
    # In /tmp (no .git), rollback is a no-op — must not crash.
    Dir.mktmpdir do |dir|
      pipe = Master::CLI::Pipeline.new([ErrStage.new(:validation)], root: dir)
      result = pipe.call(Master::Result.ok(user_message: "hi"))
      refute result.ok?
      # No exception raised = success for this test.
    end
  end

  def test_deploy_check_blocks_when_self_scan_has_violations
    Dir.mktmpdir do |dir|
      write_rules(dir)
      bus = FakeBus.new
      scanner = FakeScanner.new([{ law: "SELF_RULE", line: 1, message: "violation" }])
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:, bus:)

      result = pipe.call(Master::Result.ok(user_message: "deploy now"))

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/deploy blocked/, result.message)
      assert_includes bus.events.map(&:first), "pipeline:blocked"
    end
  end

  def test_deploy_check_blocks_tier1_critical_principles_first
    Dir.mktmpdir do |dir|
      write_rules(dir)
      bus = FakeBus.new
      scanner = FakeScanner.new([{ law: "PRESERVE_FIRST", law_id: "PRESERVE_FIRST", line: 1, message: "breaks behavior" }])
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:, bus:)

      result = pipe.call(Master::Result.ok(user_message: "deploy now"))

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/tier1 critical/, result.message)
      assert_equal "tier1_critical", bus.events.find { |event, _| event == "pipeline:blocked" }.last[:check]
    end
  end

  def test_deploy_failure_does_not_reset_a_dirty_workspace
    Dir.mktmpdir do |dir|
      init_git_repo(dir)
      write_rules(dir)
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib", "tracked.rb"), "puts :clean\n")
      system("git", "-C", dir, "add", ".")
      system("git", "-C", dir, "commit", "-m", "baseline", out: File::NULL, err: File::NULL)
      File.write(File.join(dir, "lib", "tracked.rb"), "puts :dirty\n")
      bus = FakeBus.new
      scanner = FakeScanner.new([{ law: "PRESERVE_FIRST", law_id: "PRESERVE_FIRST", line: 1, message: "breaks behavior" }])
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:, bus:)

      result = pipe.call(Master::Result.ok(user_message: "deploy now"))

      refute result.ok?
      refute_includes bus.events.map(&:first), "pipeline:rollback"
      assert_equal "puts :dirty\n", File.read(File.join(dir, "lib", "tracked.rb"))
    end
  end

  def test_deploy_check_blocks_when_evidence_score_is_too_low
    Dir.mktmpdir do |dir|
      write_rules(dir)
      scanner = FakeScanner.new([])
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:)

      result = pipe.call(Master::Result.ok(user_message: "deploy now"))

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/evidence score 25 below 80/, result.message)
    end
  end

  def test_deploy_check_passes_with_enough_evidence
    Dir.mktmpdir do |dir|
      write_rules(dir)
      scanner = FakeScanner.new([])
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:)

      result = pipe.call(Master::Result.ok(
        user_message: "deploy now",
        metadata: { evidence: { test_pass: true, code_review: true } },
      ))

      assert result.ok?
      assert_equal "ok", result.value![:output]
    end
  end

  def test_deploy_check_skips_non_deploy_messages
    Dir.mktmpdir do |dir|
      scanner = FakeScanner.new([{ law: "SELF_RULE", line: 1, message: "violation" }])
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:)

      result = pipe.call(Master::Result.ok(user_message: "scan the project"))

      assert result.ok?
      assert_equal "ok", result.value![:output]
    end
  end

  def test_parallel_group_fails_when_any_stage_errors
    group = Master::CLI::Pipeline::ParallelGroup.new(AddStage.new(:a, 1), ErrStage.new)

    result = group.call({ base: true })

    refute result.ok?
    assert_match(/parallel group failed:.*boom/, result.message)
  end

  private

  def write_rules(root)
    FileUtils.mkdir_p(File.join(root, "data"))
    File.write(File.join(root, "data", "laws.yml"), <<~YAML)
      evidence_scoring:
        weights:
          test_pass: 35
          scan_clean: 25
          code_review: 20
        pass_threshold: 80
    YAML
  end

  def init_git_repo(root)
    system("git", "-C", root, "init", "-q")
    system("git", "-C", root, "config", "user.email", "test@example.invalid")
    system("git", "-C", root, "config", "user.name", "Test")
  end
end
