# frozen_string_literal: true

require_relative "test_helper"
require "cli/council_crit"
require "cli/deliberation_prep"
require "cli/fold_risk"
require "cli/pipeline_context"

class TestCLI < Minitest::Test
  def setup
    @session     = Minitest::Mock.new
    @agent       = Minitest::Mock.new
    @renderer    = Minitest::Mock.new
    @logging     = Minitest::Mock.new
    @undo        = Minitest::Mock.new
    @config      = Minitest::Mock.new

    @config.expect(:[], false, ["tts"])
    @config.expect(:prescan?, false)

    @container = {
      session:  @session,
      agent:    @agent,
      renderer: @renderer,
      logging:  @logging,
      undo:     @undo,
      config:   @config,
    }

    @cli = Master::CLI::Session.new(container: @container)
    refute Fiber[:master_visitor], "local CLI is the operator surface, not a visitor"
  end

  # Local CLI is the operator surface. Visitor is a web-request flag.
  def teardown
    Fiber[:master_visitor] = nil
    Fiber[:master_paired] = nil
    Fiber[:master_pair_subject] = nil
  end

  # Reading a pass report aloud from the top takes longer than the pass did.
  # Its milestones are spoken as they happen, so the report has only its
  # closing line left to say.
  def test_a_pass_report_is_spoken_as_its_footer_and_a_reply_whole
    session = Master::CLI::Session.allocate
    report = [
      "review0 at master0: ., balanced",
      "mode0 at review0: balanced, full scan, council off, 8 fix passes",
      "obs0 at review0: observe",
      "scan0: done, 1127 files, 87 violations in 22 files",
      "fix0 at review0: repair",
      "fix0: pass 1, 12 of 87 fixed",
      "change0 at review0: changes",
      "change0: abc1234 Master: a repair",
      "review0: complete, 87 findings, 41 after the fix",
    ].join("\n")

    assert_equal "review0: complete, 87 findings, 41 after the fix", session.send(:spoken_form, report)
    assert_equal "the pool is every model this machine can reach.",
                 session.send(:spoken_form, "the pool is every model this machine can reach.")
  end

  def test_the_lines_spoken_while_a_pass_runs_are_its_milestones
    milestone = Master::CLI::Session::MILESTONE

    ["obs0: done, 1127 files, 87 violations in 22 files", "scan0: pass 1, 5 violations",
     "fix0: pass 1, 12 of 87 fixed", "review0: complete, 601s"].each do |line|
      assert_match milestone, line
    end
    ["obs0: 113/1127 files, 0 violations in 0 files, 35s, eta 311s",
     "scan0: 194 model calls, 178 failed, 4 lanes",
     "llm8 at obs0: ollama:qwen2.5-coder:3b"].each do |line|
      refute_match milestone, line, "a torrent line must not be spoken"
    end
  end

  def test_tts_status_is_one_compact_dmesg_record
    registry = Master::CLI::CommandRegistry.allocate
    status = registry.send(:voice_status)

    refute_match(/[\r\n]/, status)
    assert_match(/\Avoice0 at mainbus0: (?:on|off); player=/, status)
    assert_includes status, "timing="
  end

  def test_container_accessor
    assert_same @container, @cli.container
  end

  def test_scan_report_uses_inverted_pyramid_order
    findings = [
      { law: "STYLE", line: 2, message: "style issue" },
      { law: "STYLE", line: 3, message: "another style issue" },
      { law: "SECURITY", line: 8, message: "security issue" },
    ]
    output = Master::CLI::Scan::Report.new(
      pairs: [["sample.rb", Master::Result.ok(findings)]],
      profile: nil,
      rule_filter: nil,
    ).render
    lines = output.lines.map(&:chomp)

    assert_equal "3 total violations", lines[0]
    assert_equal "STYLE 2", lines[1]
    assert_operator lines.index("STYLE 2"), :<, lines.find_index { |l| l.start_with?("  sample.rb:2 style issue") }
  end

  def test_scan_dry_run_report_says_no_changes_made
    findings = [{ law: "STYLE", line: 2, message: "style issue" }]

    output = Master::CLI::Scan::Report.new(
      pairs: [["sample.rb", Master::Result.ok(findings)]],
      profile: nil,
      rule_filter: nil,
      dry_run: true,
    ).render

    assert_match(/\Adry-run: 1 total violations \(no changes made\)/, output)
  end

  def test_command_maps_positional_dependencies_to_keyword_handler
    receiver = Module.new do
      module_function

      def dispatch_example(root:, ctx: nil)
        "#{root}:#{ctx[:args]}"
      end
    end
    command = Master::CLI::CommandRegistry::Command.new(receiver, :dispatch_example, "/tmp/root")

    assert_equal "/tmp/root:ok", command.call(args: "ok")
  end

  def test_deliberation_prep_publishes_and_returns_nil_when_ideation_fails
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    container = { agent: Object.new, bus: }

    Master::CLI::DeliberationPrep.stub(:run_ideation, ->(*) { raise "ideation unavailable" }) do
      assert_nil Master::CLI::DeliberationPrep.prepare!(goal: "goal", container:, risk: :high)
    end

    assert_equal ["ideation:error", { message: "ideation unavailable" }], events.last
  end

  def test_council_crit_returns_clean_for_an_empty_diff
    Master::CLI::CouncilCrit.stub(:diff_artifact, " \n") do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation: Object.new)

      assert result.ok?
      assert_equal "critique: no changes to review", result.value!
    end
  end

  def test_council_crit_does_not_turn_git_failure_into_empty_diff
    Master::CLI::CouncilCrit.stub(:git_capture, ->(*) { raise "git unavailable" }) do
      result = Master::CLI::CouncilCrit.run(
        root: "/tmp/master",
        deliberation: Object.new,
      )

      assert result.err?
      assert_includes result.message, "critique: git unavailable"
      assert_equal :infrastructure, result.category
    end
  end

  def test_council_crit_reports_missing_deliberation
    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff --git a/a b/a\n") do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation: nil)

      assert result.err?
      assert_equal "critique: deliberation unavailable", result.message
      assert_equal :infrastructure, result.category
    end
  end

  def test_council_crit_fails_closed_without_the_security_gated_entrypoint
    deliberation = Object.new
    deliberation.define_singleton_method(:review) do |_artifact, context:|
      Master::Result.ok([{ persona: "Rhea", feedback: context, role: "Reviewer" }])
    end

    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff") do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation:)

      assert result.err?
      assert_equal :infrastructure, result.category
      assert_includes result.message, "Security-gated pre-ship review unavailable"
    end
  end

  def test_council_crit_publishes_a_real_veto_and_preserves_error
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    deliberation = Object.new
    deliberation.define_singleton_method(:review_pre_ship) do |_artifact, context:|
      raise "unexpected context: #{context}" unless context == "pre-ship council check (staged)"

      Master::Result.err("council: veto from Security\ncritical finding", category: :validation)
    end

    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff") do
      result = Master::CLI::CouncilCrit.run(
        root: "/tmp/master",
        deliberation:,
        scope: "staged",
        bus:,
      )

      assert_equal "council: veto from Security\ncritical finding", result.message
      assert_equal ["council:start", { scope: "staged", bytes: 4 }], events[0]
      assert_equal(
        ["council:veto", {
          vetoed_by: "Security",
          veto_exercised: true,
          security_veto_exercised: true,
          message: "council: veto from Security\ncritical finding",
        }],
        events[1],
      )
    end
  end

  def test_council_crit_does_not_classify_an_unknown_name_as_a_veto
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    deliberation = Object.new
    deliberation.define_singleton_method(:review_pre_ship) do |_artifact, context:|
      Master::Result.err("council: veto from Pretender\nclaimed block", category: :validation)
    end

    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff") do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation:, bus:)

      assert result.err?
      assert_equal :validation, result.category
      assert_equal "council:inconclusive", events.last.first
      refute events.any? { |event, _details| event == "council:veto" }
    end
  end

  def test_council_crit_does_not_pass_without_returned_security_evidence
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    deliberation = Object.new
    deliberation.define_singleton_method(:review_pre_ship) do |_artifact, context:|
      Master::Result.ok([{ persona: "Rhea", feedback: "looks good", role: "Reviewer" }])
    end

    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff") do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation:, bus:)

      assert result.err?
      assert_equal :inconclusive, result.category
      assert_includes result.message, "Security reviewer did not complete"
      assert_equal "council:inconclusive", events.last.first
      refute events.any? { |event, _details| event == "council:pass" }
    end
  end

  def test_council_crit_does_not_call_unavailable_reviewers_a_veto
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    deliberation = Object.new
    deliberation.define_singleton_method(:review_pre_ship) do |_artifact, context:|
      Master::Result.err("council: required veto reviewer(s) did not answer: Security", category: :inconclusive)
    end

    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff") do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation:, bus:)

      assert result.err?
      assert_equal :inconclusive, result.category
      assert_equal "council:inconclusive", events.last.first
      assert_equal "inconclusive", events.last.last[:category]
      assert_includes events.last.last[:reason], "Security"
      refute events.any? { |event, _details| event == "council:veto" }
    end
  end

  def test_council_crit_summarizes_pass_and_truncates_large_artifacts
    reviewed = nil
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    deliberation = Object.new
    deliberation.define_singleton_method(:review_pre_ship) do |artifact, context:|
      raise "unexpected context: #{context}" unless context == "pre-ship council check (diff)"

      reviewed = artifact
      Master::Result.ok(
        [
          { persona: "Security", role: "Security Review", veto_role: true, feedback: "no critical issue" },
          { persona: "Rhea", feedback: "looks good\nwith detail", role: "Reviewer" },
          { persona: "Synthesis", feedback: "ship it", role: "Synthesis" },
        ],
      )
    end
    status = Object.new
    status.define_singleton_method(:success?) { true }
    Master::Io::Exec.stub(:capture2e, ["x" * 40_000, status]) do
      result = Master::CLI::CouncilCrit.run(root: "/tmp/master", deliberation:, bus:)

      assert result.ok?
      assert_includes result.value!, "critique: council pass"
      assert_includes result.value!, "Rhea: looks good"
      assert_includes result.value!, "synthesis: ship it"
      assert_equal Master::CLI::CouncilCrit::MAX_DIFF_BYTES + "\n... [truncated]".bytesize, reviewed.bytesize
      assert_equal(
        ["council:pass", {
          jurors: 3,
          veto_roles_answered: ["Security"],
          security_reviewed: true,
          veto_exercised: false,
          security_veto_exercised: false,
        }],
        events.last,
      )
    end
  end

  def test_council_crit_runner_uses_container_dependencies
    deliberation = Object.new
    deliberation.define_singleton_method(:review_pre_ship) do |_artifact, context:|
      Master::Result.ok([{ persona: "Security", feedback: context, role: "Security Review", veto_role: true }])
    end
    bus = Object.new
    bus.define_singleton_method(:publish) { |_event, **_details| }
    runner = Master::CLI::CouncilCrit.runner_for({ deliberation:, bus: })

    Master::CLI::CouncilCrit.stub(:diff_artifact, "diff") do
      result = runner.call(root: "/tmp/master")

      assert_includes result.value!, "Security: pre-ship council check (diff)"
    end
  end

  def test_help_uses_progressive_disclosure
    summary = Master::CLI::CommandRegistry.help_text
    fix = Master::CLI::CommandRegistry.help_text("fix")

    assert_match(/^input0 at master0: describe work in plain language/, summary)
    assert_match(/^try0 at master0:/, summary)
    assert_match(/^keys0 at master0: Tab suggests common commands/, summary)
    assert_match(%r{^fix0 at master0: /fix \[path\]$}, summary)
    assert_match(/^health0 at master0: \/status \/doctor$/, summary)
    assert_match(/^help0 at master0: \/help \[command\]$/, summary)
    refute_includes summary, "--dry-run"
    # The reading is /fix's flags, named on its page; /help review is the /fix
    # page because /review is the reading spelling of /fix.
    assert_includes fix, "--only", "the stages are the detail, not the summary"
    assert_equal fix, Master::CLI::CommandRegistry.help_text("review")
    assert_equal fix, Master::CLI::CommandRegistry.help_text("critique")
    assert_includes fix, "--dry-run", "the flag that holds the repair back is the detail"
    assert_includes Master::CLI::CommandRegistry.help_text("model"), "/model status and /model current"
  end

# /commit is built with review_check: true, so the page has to name the flag
# the check asks for, and the path list that scopes what goes in.
def test_commit_help_names_the_paths_and_the_confirm_flag
  detail = Master::CLI::CommandRegistry.help_text("commit")

  assert_includes detail, "<path>"
  assert_includes detail, Master::CLI::CommandRegistry::Command::CONFIRM_FLAG
  refute_includes detail, "git add -u"
end

  def test_terminal_approval_is_resolved_by_the_shared_input_loop
    request = { answer: nil, choices: [] }
    @cli.instance_variable_set(:@pending_terminal_ask, request)

    assert @cli.send(:terminal_ask_pending?)
    assert @cli.send(:answer_pending_terminal_ask, "/approve")
    assert_equal "yes", request[:answer]
  end

  def test_invalid_terminal_approval_input_is_not_consumed
    request = { answer: nil, choices: [] }
    @cli.instance_variable_set(:@pending_terminal_ask, request)

    refute @cli.send(:answer_pending_terminal_ask, "follow-up message")
    assert_nil request[:answer]
  end

  def test_interactive_queue_refuses_overflow_without_dropping_pending_messages
    queue = @cli.instance_variable_get(:@turn_queue)
    @cli.instance_variable_get(:@turn_queue_mutex).synchronize do
      Master::CLI::Session::INTERACTIVE_QUEUE_LIMIT.times { |index| queue << "pending #{index + 1}" }
    end

    output, = capture_io { @cli.send(:enqueue_interactive_line, "overflow") }

    assert_equal Master::CLI::Session::INTERACTIVE_QUEUE_LIMIT, queue.length
    assert_match(/full, #{Master::CLI::Session::INTERACTIVE_QUEUE_LIMIT} pending; message not queued/, output)
  end

  def test_stop_pauses_without_discarding_messages_and_resume_restarts_the_queue
    queue = @cli.instance_variable_get(:@turn_queue)
    @cli.instance_variable_get(:@turn_queue_mutex).synchronize { queue << "follow-up" }

    output, = capture_io { @cli.send(:stop_interactive_queue) }
    assert_match(/queue paused; pending turn will not start/, output)
    assert_equal ["follow-up"], queue
    assert @cli.instance_variable_get(:@turn_queue_paused)
    assert @cli.instance_variable_get(:@turn_cancel_requested)

    @cli.stub(:start_interactive_queue_worker_locked, -> { @cli.instance_variable_set(:@queue_worker_started_for_test, true) }) do
      output, = capture_io { @cli.send(:resume_interactive_queue) }
      assert_match(/resuming, 1 queued/, output)
    end
    refute @cli.instance_variable_get(:@turn_queue_paused)
    refute @cli.instance_variable_get(:@turn_cancel_requested)
    assert @cli.instance_variable_get(:@queue_worker_started_for_test)
    assert_equal ["follow-up"], queue
  end

  def test_cancelled_pipeline_result_is_classified_as_abort
    thread = Thread.new { sleep 60 }
    thread.kill
    thread.join
    @cli.instance_variable_set(:@pipeline_thread, thread)
    @cli.instance_variable_set(:@turn_cancel_requested, true)

    result = @cli.send(:fetch_pipeline_result)

    assert_equal :abort, result.category
    assert_equal "interrupted", result.message
  ensure
    thread&.kill
  end

  def test_queue_overflow_reports_rejection_to_callers
    queue = @cli.instance_variable_get(:@turn_queue)
    @cli.instance_variable_get(:@turn_queue_mutex).synchronize do
      Master::CLI::Session::INTERACTIVE_QUEUE_LIMIT.times { queue << "pending" }
    end

    capture_io do
      refute @cli.send(:enqueue_interactive_line, "must remain a draft")
    end
    assert_equal Master::CLI::Session::INTERACTIVE_QUEUE_LIMIT, queue.length
  end

  def test_stop_before_execution_requeues_the_dequeued_line
    queue = @cli.instance_variable_get(:@turn_queue)
    line = "keep this pending"
    @cli.instance_variable_get(:@turn_queue_mutex).synchronize do
      queue.clear
      @cli.instance_variable_set(:@turn_queue_paused, true)
      @cli.instance_variable_set(:@turn_current_line, line)
      @cli.instance_variable_set(:@turn_current_started, false)
    end

    refute @cli.send(:begin_interactive_line, line)

    assert_equal [line], queue
    assert_nil @cli.instance_variable_get(:@turn_current_line)
    refute @cli.instance_variable_get(:@turn_current_started)
  end

  def test_dispatch_turn_refuses_to_start_after_a_stop_race
    @cli.instance_variable_set(:@turn_cancel_requested, true)

    result = @cli.send(:dispatch_turn, "must not start", accumulated: +"", state: {})

    refute result.ok?
    assert_match(/cancelled before dispatch/, result.message)
    assert_nil @cli.instance_variable_get(:@pipeline_thread)
  end

  def test_interactive_queue_processes_submissions_in_order
    seen = []
    started = Queue.new
    release = Queue.new
    handler = lambda do |line|
      seen << line
      if line == "first"
        started << true
        release.pop
      end
    end

    @cli.stub(:handle_repl_line, handler) do
      capture_io do
        @cli.send(:enqueue_interactive_line, "first")
        started.pop
        @cli.send(:enqueue_interactive_line, "second")
        release << true
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          break if seen == %w[first second] && @cli.instance_variable_get(:@turn_worker).nil?
          sleep 0.01
        end
      end
    end

    assert_equal %w[first second], seen
    assert_nil @cli.instance_variable_get(:@turn_worker)
  end

  def test_prompt_state_is_announced_before_reline_owns_the_input_row
    session = Master::CLI::Session.allocate
    events = []
    session.instance_variable_set(:@reading_input, false)
    session.define_singleton_method(:prompt_for_mode) do
      events << [:prompt, @reading_input]
      terminal_puts("state0")
      "master$ "
    end
    session.define_singleton_method(:terminal_puts) do |text = "", **|
      events << [:announce, @reading_input, text]
    end
    session.define_singleton_method(:reserve_activity_row) do
      events << [:reserve, @reading_input]
    end
    session.define_singleton_method(:safe_read_line) do |prompt|
      events << [:read, @reading_input, prompt]
      "hello"
    end

    assert_equal "hello", session.send(:read_prompt_line)
    assert_equal [
      [:prompt, false],
      [:announce, false, "state0"],
      [:reserve, true],
      [:read, true, "master$ "],
    ], events
    refute session.instance_variable_get(:@reading_input)
  end

  def test_transient_reline_read_error_does_not_masquerade_as_ctrl_d
    result = nil
    capture_io do
      Reline.stub(:readline, ->(*) { raise RuntimeError, "transient input read failed" }) do
        result = @cli.send(:safe_read_line, "master$ ")
      end
    end

    assert_equal :interrupted, result
  end

  def test_reline_closed_terminal_is_treated_as_eof
    result = nil
    capture_io do
      Reline.stub(:readline, ->(*) { raise IOError, "terminal closed" }) do
        result = @cli.send(:safe_read_line, "master$ ")
      end
    end

    assert_nil result
  end

  # The foreign-write protocol: an operator-facing write from any lane clears
  # the draft's row, steps below it, and the redisplay rebuilds the editable
  # line at the payload's end. Without the repaint Reline's differential
  # render paints nothing its cache still matches, and the prompt stays gone
  # after the first message.
  DraftIO = Class.new do
    def initialize
      @buffer = +""
    end
    attr_reader :buffer

    def tty? = true
    def isatty = true
    def write(text) = @buffer << text
    def print(text) = @buffer << text
    def puts(text = "") = @buffer << text << "\n"
    def flush = @buffer
  end

  def with_redisplay_counter
    counter = []
    original = Reline.method(:redisplay)
    Reline.singleton_class.send(:define_method, :redisplay, -> { counter << 1 })
    yield counter
  ensure
    Reline.singleton_class.send(:define_method, :redisplay, original)
  end

  def test_a_foreign_write_clears_the_draft_without_leaving_an_empty_spinner_row
    io = DraftIO.new
    alive = Object.new
    alive.define_singleton_method(:alive?) { true }
    @cli.instance_variable_set(:@reading_input, true)
    @cli.instance_variable_set(:@turn_worker, alive)
    @cli.instance_variable_set(:@spin_thread, alive)

    with_redisplay_counter do |counter|
      @cli.send(:terminal_write, io:) { |target| target.puts("turn0: reply row") }

      assert_equal "\r\e[K\r\nturn0: reply row\n", io.buffer
      assert_equal [1], counter
      assert_kind_of Numeric, @cli.instance_variable_get(:@last_foreign_write_at)
    end
  end

  def test_spinner_row_waits_for_a_quiet_gap_after_foreign_output
    io = DraftIO.new
    alive = Object.new
    alive.define_singleton_method(:alive?) { true }
    redraws = []
    @cli.instance_variable_set(:@reading_input, true)
    @cli.instance_variable_set(:@turn_worker, alive)
    @cli.instance_variable_set(:@activity_row_reserved, false)
    @cli.instance_variable_set(:@turn_queue_paused, false)
    @cli.instance_variable_set(:@closed, false)
    @cli.instance_variable_set(:@last_foreign_write_at, Process.clock_gettime(Process::CLOCK_MONOTONIC))

    @cli.stub(:redraw_active_input, -> { redraws << true }) do
      @cli.send(:reserve_activity_row_after_quiet, io)
      assert_empty io.buffer
      refute @cli.instance_variable_get(:@activity_row_reserved)

      @cli.instance_variable_set(:@last_foreign_write_at,
                                 Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
      @cli.send(:reserve_activity_row_after_quiet, io)
    end

    assert_equal "\n", io.buffer
    assert @cli.instance_variable_get(:@activity_row_reserved)
    assert_equal [true], redraws
  end

  def test_a_non_tty_write_takes_no_draft_rows_or_redisplays
    io = StringIO.new
    @cli.instance_variable_set(:@reading_input, true)

    with_redisplay_counter do |counter|
      @cli.send(:terminal_write, io:) { |target| target.puts("plain") }

      assert_equal "plain\n", io.string
      assert_empty counter
    end
  end

  def test_a_failing_redisplay_keeps_the_payload_visible
    io = DraftIO.new
    @cli.instance_variable_set(:@reading_input, true)
    original = Reline.method(:redisplay)
    Reline.singleton_class.send(:define_method, :redisplay, -> { raise IOError, "render raced" })

    @cli.send(:terminal_write, io:) { |target| target.puts("kept") }

    assert_includes io.buffer, "kept"
  ensure
    Reline.singleton_class.send(:define_method, :redisplay, original)
  end

  def test_stream_chunks_claim_one_row_and_grow_without_guard_round_trips
    io = DraftIO.new
    stream = $stdout
    $stdout = io
    state = {}

    with_redisplay_counter do |counter|
      @cli.instance_variable_set(:@reading_input, true)
      @cli.send(:handle_stream_text, "hello", state)
      @cli.send(:handle_stream_text, " there", state)

      assert_equal "\r\nhello there", io.buffer
      assert_empty counter
      assert state[:stream_row_open]
    end
  ensure
    $stdout = stream
  end

  def test_model_greeting_is_opt_in_to_protect_the_first_operator_turn
    previous = ENV.delete("MASTER_GREETING")
    spawned = false

    Thread.stub(:new, ->(*_args, &_block) { spawned = true }) do
      $stdout.stub(:tty?, true) { @cli.send(:greet_from_model) }
    end

    refute spawned
  ensure
    ENV["MASTER_GREETING"] = previous if previous
  end

  def test_prompt_refreshes_skills_before_rendering
    skills = Minitest::Mock.new
    skills.expect(:discover!, [])
    session = Struct.new(:phase, :token_est, :cost).new(:ready, 0, 0.0)
    agent = Struct.new(:model).new("test-model")
    renderer = Object.new
    renderer.define_singleton_method(:prompt_line) { |*_args, **_options| [nil, "master$ "] }

    cli = Master::CLI::Session.new(
      container: {
        session:,
        agent:,
        renderer:,
        logging: Object.new,
        undo: Object.new,
        config: {},
        pipeline: Object.new,
        skills:,
      },
    )
    cli.instance_variable_set(:@focus_mode, true)

    output = cli.send(:prompt_for_mode)

    assert_equal "master$ ", output
    skills.verify
  end

  # A pass hands the critique a file as its root; git -C needs the file's directory.
  def test_the_critique_diff_of_a_file_runs_in_its_directory_limited_to_the_file
    Dir.mktmpdir do |dir|
      identity = %w[-c user.email=t@t -c user.name=t]
      git = ->(*args) { Master::Io::Exec.capture2e("git", "-C", dir, *identity, *args) }

      file = File.join(dir, "a.rb")
      git.call("init", "-q")
      File.write(file, "A = 1\n")
      git.call("add", "a.rb")
      git.call("commit", "-q", "-m", "a")
      File.write(file, "A = 2\n")
      File.write(File.join(dir, "b.rb"), "B = 1\n")

      diff = Master::CLI::CouncilCrit.diff_artifact(file, scope: "diff")

      assert_includes diff, "+A = 2"
      refute_includes diff, "b.rb"
    end
  end

  def test_model_list_is_one_row_per_model_with_the_current_one_marked
    agent = Struct.new(:model).new("ollama:gemma3:4b")
    rows = Master::CLI::CommandRegistry.list_models(root: Master::ROOT, metrics: nil, agent:).lines

    assert_equal rows.size, rows.map { |row| row.split[row.start_with?("->") ? 1 : 0] }.uniq.size
    # Which tiers list the model is models.yml's to say; the row names the
    # current model once, marked, with its tiers after it.
    current = rows.find { |row| row.start_with?("->") }
    assert_match(/\A-> ollama:gemma3:4b +\S/, current)
    assert_includes current.split.drop(2).join(" "), "local"
  end

  # The pool lists what answers and names what would add more; a model out of
  # reach is refused with its fix, or swapped for the same model on a lane the
  # pool has.
  def test_model_list_shows_the_pool_and_model_refuses_what_it_cannot_reach
    router = Object.new
    def router.unreachable_reason(id, wait: false) = id == "gemini-2.5-flash" || id == "o3" ? "set GEMINI_API_KEY" : nil
    def router.pool(wait: false) = %w[nvidia/nemotron-3-super-120b-a12b:free google/gemini-2.5-flash]
    def router.pool_growth(wait: false) = ["set GEMINI_API_KEY"]
    def router.lane_label(_id) = "free"
    agent = Struct.new(:model, :model_router).new("nvidia/nemotron-3-super-120b-a12b:free", router)
    config = Struct.new(:saved) { def save! = self.saved = true }.new

    listing = Master::CLI::CommandRegistry.list_models(root: Master::ROOT, metrics: nil, agent:)
    assert_match(/^-> nvidia\/nemotron-3-super-120b-a12b:free +grok_primary/, listing)
    assert_match(/^more with:\n  set GEMINI_API_KEY/, listing)

    output = Master::CLI::CommandRegistry.dispatch_model(agent:, config:, metrics: nil, root: Master::ROOT, arg: "gemini-2.5-flash")
    assert_equal "google/gemini-2.5-flash", agent.model
    assert_match(/itself needs: set GEMINI_API_KEY/, output)

    refused = Master::CLI::CommandRegistry.dispatch_model(agent:, config:, metrics: nil, root: Master::ROOT, arg: "o3")
    assert_equal "model: o3 is out of reach: set GEMINI_API_KEY", refused
    assert_equal "google/gemini-2.5-flash", agent.model
  end

  def test_dispatch_model_status_and_current_never_change_the_selected_model
    agent = Struct.new(:model).new("grok-cli:auto")
    config = { "model" => "grok-cli:auto" }

    Master::Io::LaneSelection.stub(:primary_report, "first live lane") do
      %w[status current STATUS CURRENT].each do |arg|
        output = Master::CLI::CommandRegistry.dispatch_model(
          agent:, config:, metrics: nil, root: Master::ROOT, arg:
        )

        assert_equal "model: grok-cli:auto; first live lane; /model pick chooses with arrows; /model list names the others", output
        assert_equal "grok-cli:auto", agent.model
      end
    end
  end

  def test_model_pick_uses_tty_prompt_arrows_filter_and_only_the_live_pool
    router = Object.new
    def router.unreachable_reason(_id, wait: false) = nil
    def router.pool(wait: false) = %w[google/gemini-2.5-flash nvidia/nemotron-3-super-120b-a12b:free]
    def router.lane_label(_id) = "live"
    agent = Struct.new(:model, :model_router).new("google/gemini-2.5-flash", router)
    config = Struct.new(:saved) { def save! = self.saved = true }.new
    prompt_state = {}
    prompt = Object.new
    prompt.define_singleton_method(:select) do |question, choices, **options|
      prompt_state[:question] = question
      prompt_state[:choices] = choices
      prompt_state[:options] = options
      choices.last.fetch(:value)
    end

    output = nil
    $stdin.stub(:tty?, true) do
      $stdout.stub(:tty?, true) do
        TTY::Prompt.stub(:new, prompt) do
          output = Master::CLI::CommandRegistry.dispatch_model(
            agent:, config:, metrics: nil, root: Master::ROOT, arg: "pick"
          )
        end
      end
    end

    assert_equal "model: nvidia/nemotron-3-super-120b-a12b:free", output
    assert_equal "nvidia/nemotron-3-super-120b-a12b:free", agent.model
    assert config.saved
    assert_equal "Choose a reachable model", prompt_state.fetch(:question)
    assert_equal %w[google/gemini-2.5-flash nvidia/nemotron-3-super-120b-a12b:free],
                 prompt_state.fetch(:choices).map { |choice| choice.fetch(:value) }
    assert_match(/\(current\)\z/, prompt_state.fetch(:choices).first.fetch(:name))
    assert_equal prompt_state.fetch(:choices).first.fetch(:name), prompt_state.fetch(:options).fetch(:default)
    assert_equal 12, prompt_state.fetch(:options).fetch(:per_page)
    assert_equal true, prompt_state.fetch(:options).fetch(:cycle)
    assert_equal true, prompt_state.fetch(:options).fetch(:filter)
  end

  def test_model_pick_refuses_non_interactive_output_without_switching
    agent = Struct.new(:model, :model_router).new("grok-cli:auto", nil)
    config = Object.new

    output = $stdin.stub(:tty?, false) do
      Master::CLI::CommandRegistry.dispatch_model(
        agent:, config:, metrics: nil, root: Master::ROOT, arg: "pick"
      )
    end

    assert_match(/needs an interactive terminal/, output)
    assert_equal "grok-cli:auto", agent.model
  end

  def test_dispatch_model_switches_active_model
    agent = Struct.new(:model).new("openrouter/auto")
    config = Minitest::Mock.new
    config.expect(:save!, nil)

    output = Master::CLI::CommandRegistry.dispatch_model(
      agent:,
      config:,
      metrics: nil,
      root: Dir.pwd,
      arg: "gpt-4o",
    )

    assert_equal "model: gpt-4o", output
    assert_equal "gpt-4o", agent.model
    config.verify
  end

  def test_scan_profile_uses_explicit_keyword
    profile, = Master::CLI::Scan::Request.resolve_scan_profile("critical lib", Dir.pwd)
    plain, = Master::CLI::Scan::Request.resolve_scan_profile("criticality.rb", Dir.pwd)

    assert_equal "critical", profile
    assert_nil plain
  end

  def test_legacy_quick_scan_profile_resolves_to_core_report_filter
    profile, = Master::CLI::Scan::Request.resolve_scan_profile("quick lib", Master::ROOT)

    assert_equal "core", profile
  end

  # The closed set is what the list offers. /fix is in it, because it is the
  # operation that writes and what a person types. /scan is not, and must not
  # come back as a row: a second entry in the list is a second command.
  def test_help_names_the_closed_set
    summary = Master::CLI::CommandRegistry.help_text
rows = summary.scan(%r{(?<=\s)/(\w+)}).flatten
%w[status undo commit model doctor laws why orders soul help clear].each do |name|
  assert_includes rows, name
end
assert_includes rows, "fix"
# The list is the topics: a documented command missing from it is a command nobody finds.
topics = Master::CLI::CommandRegistry::HELP_TOPICS.keys
assert_empty topics - rows, "documented commands missing from the summary"
    refute_includes rows, "scan"
    refute_includes summary, "/orient"
    refute_includes summary, "/scan"
  end

  # ^C during a turn took the REPL down with "undefined method ok? for nil".
  # signals.rb kills the pipeline thread, Thread#value answers nil for a killed
  # thread rather than raising, and session.rb:88 called result.ok? on it.
  # Neither rescue in fetch_pipeline_result could have caught it: Interrupt is
  # not a StandardError and a killed thread raises nothing at all.
  def test_a_killed_pipeline_thread_yields_a_result_not_nil
    thread = Thread.new { sleep 5 }
    sleep 0.05
    thread.kill

    assert_nil thread.value, "a killed thread answers nil, which is the shape of the crash"
    @cli.instance_variable_set(:@pipeline_thread, thread)

    result = @cli.send(:fetch_pipeline_result)

    assert_kind_of Master::Result, result
    refute_predicate result, :ok?
  end

  def test_script_error_from_pipeline_becomes_an_infrastructure_result
    failure = SyntaxError.new("invalid source in child turn")
    pipeline = Object.new
    pipeline.define_singleton_method(:value) { raise failure }
    @cli.instance_variable_set(:@pipeline_thread, pipeline)

    result = @cli.send(:fetch_pipeline_result)

    assert_equal :infrastructure, result.category
    assert_includes result.message, "SyntaxError"
    assert_includes result.message, "invalid source in child turn"
  end

  def test_memory_error_from_pipeline_becomes_a_named_infrastructure_result
    failure = NoMemoryError.new("simulated allocation failure")
    pipeline = Object.new
    pipeline.define_singleton_method(:value) { raise failure }
    @cli.instance_variable_set(:@pipeline_thread, pipeline)
    @cli.stub(:host_oom_message, "host memory exhausted") do
      result = @cli.send(:fetch_pipeline_result)

      assert_equal :infrastructure, result.category
      assert_equal "host memory exhausted", result.message
    end
  end

  def test_process_exit_and_signal_interrupt_escape_the_pipeline_result_boundary
    [SystemExit.new(23), Interrupt.new("operator interrupt")].each do |failure|
      pipeline = Object.new
      pipeline.define_singleton_method(:value) { raise failure }
      @cli.instance_variable_set(:@pipeline_thread, pipeline)

      observed = assert_raises(failure.class) { @cli.send(:fetch_pipeline_result) }
      assert_same failure, observed
    end
  end

  # user:interrupt had a publisher and no subscriber, so a cancelled turn's
  # subprocesses ran on. The event now carries the turn's children, and the
  # boot subscriber kills them.
  def test_ctrl_c_during_a_turn_kills_the_turn_and_its_children
    bus = Master::Trace::EventBus.new(event_log: Object.new.tap { |log| log.define_singleton_method(:append) { |*| nil } })
    Master::Builder::TraceBoot.allocate.send(:subscribe_interrupt, bus)
    children = Master::Io::Exec::Children.new
    cli = Master::CLI::Session.new(container: @container.merge(bus:))
    turn = Thread.new do
      Fiber[:master_children] = children
      Master::Io::Exec.capture2e("sh", "-c", "sleep 30")
    end
    sleep 0.3
    cli.instance_variable_set(:@pipeline_thread, turn)
    cli.instance_variable_set(:@turn_children, children)

    cli.send(:on_int).join(3)

    assert turn.join(3), "the turn's thread must be dead"
    assert_equal 0, children.kill_all, "the child must be gone"
  end

# A turn printed every bus event, 28,700 lines for one /fix reading, and then
# nothing but its writes. Now it prints what the model does, as dmesg units:
# each call, file and request attaches and reports; scan chatter stays out.
def publish_a_call_and_a_fetch(bus)
  model = "nvidia/nemotron-3-super-120b-a12b:free"
  bus.publish("scan:pass", pass: "lexical", rule_count: 131)
  bus.publish("error:swallowed", context: "anything")
  bus.publish("llm:send", model:)
  bus.publish("llm:call_complete", model:, tokens_in: 900, tokens_out: 40)
  bus.publish("llm:provider_outcome", model:, status: :success, latency_ms: 2100)
  bus.publish("tool:call", tool: "web_fetch", subject: "https://www.openbsd.org/")
  bus.publish("tool:return", tool: "web_fetch", ok: true, bytes: 14_203, ms: 310)
end

def test_spinner_names_the_provider_actually_waiting_or_streaming
  assert_equal "waiting claude-cli",
               @cli.send(:stage_for, "llm:send", model: "claude-cli:claude-opus-5-5")
  assert_equal "streaming grok-cli",
               @cli.send(:stage_for, "llm:stream_started", model: "grok-cli:auto")
end

def test_spinner_provider_changes_when_a_fallback_lane_is_sent
  stages = [
    @cli.send(:stage_for, "llm:send", model: "claude-cli:claude-opus-5-5"),
    @cli.send(:stage_for, "llm:send", model: "agy:gemini-3.1-pro-high"),
  ]

  assert_equal ["waiting claude-cli", "waiting agy"], stages
end

def test_spinner_provider_label_drops_terminal_control_characters
  stage = @cli.send(:stage_for, "llm:send", model: "bad\e[31m-provider:model")

  refute_match(/\e|\[31m/, stage)
  assert_match(/\Awaiting /, stage)
end

def test_a_turn_prints_its_units_and_nothing_else
  silent_log = Object.new.tap { |log| log.define_singleton_method(:append) { |*| nil } }
  bus = Master::Trace::EventBus.new(event_log: silent_log)
  logging = Master::Trace::Logging.new(ring_buffer: [], event_bus: bus)
  renderer = Object.new
  renderer.define_singleton_method(:render) { |text, mode:| text }
  cli = Master::CLI::Session.new(container: @container.merge(bus:, renderer:, logging:, root: Dir.mktmpdir))

  # Normal is the default operator mode: meaningful model/tool units print,
  # while scan churn and unrelated bus events stay out of the terminal.
  out, err = capture_io do
    Master::Trace::Dmesg.with_verbosity("normal") do
      cli.send(:init_thinking_state!)
      publish_a_call_and_a_fetch(bus)
      cli.send(:close_unit_console)
    end
  end

  lines = (out + err).split(/[\r\n]/).map { |line| line.delete_prefix("\e[K") }.reject(&:empty?)
  assert_equal [
    "llm0 at master0: nvidia/nemotron-3-super-120b-a12b",
    "llm0: 900 tokens in, 40 out, 2.1s",
    "net0 at master0: network",
    "fetch0 at net0: target redacted (24 bytes)",
    "fetch0: 14203 bytes, 0.3s",
  ], lines
end

def test_master_cli_quiet_silences_the_unit_lines
  silent_log = Object.new.tap { |log| log.define_singleton_method(:append) { |*| nil } }
  bus = Master::Trace::EventBus.new(event_log: silent_log)
  logging = Master::Trace::Logging.new(ring_buffer: [], event_bus: bus)
  renderer = Object.new
  renderer.define_singleton_method(:render) { |text, mode:| text }
  cli = Master::CLI::Session.new(container: @container.merge(bus:, renderer:, logging:, root: Dir.mktmpdir))
  previous = ENV["MASTER_CLI_QUIET"]
  ENV["MASTER_CLI_QUIET"] = "1"
  out, err = capture_io do
    Master::Trace::Dmesg.with_verbosity("normal") do
      cli.send(:init_thinking_state!)
      publish_a_call_and_a_fetch(bus)
      cli.send(:close_unit_console)
    end
  end
  assert_empty (out + err).strip
ensure
  ENV["MASTER_CLI_QUIET"] = previous
end

def test_the_fix_help_names_normal_output_as_the_default_and_quiet_as_opt_out
  help = Master::CLI::CommandRegistry.help_text("fix")
  assert_includes help, "Normal dmesg units appear automatically"
  assert_includes help, "MASTER_CLI_QUIET=1"
end

def test_ctrl_c_at_the_prompt_raises_interrupt_for_repl_loop_to_close
    assert_raises(Interrupt) { @cli.send(:on_int) }
  end

  # Every error carried "[validation] … [ship_proof_not_checkboxes] Backlog
  # marked done but production gaps remain", a lesson about something else.
  def test_an_error_prints_its_message_alone
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, mode:| "#{mode}: #{text}" }
    cli = Master::CLI::Session.new(container: @container.merge(renderer:))

    out, = capture_io do
      cli.send(:display_result, result: Master::Result.err("unknown command: /dmesg", category: :validation), accumulated: "", streamed: false)
    end

    assert_equal "err0: unknown command: /dmesg\n", out
  end

  def test_a_cancelled_turn_prints_nothing
    out, = capture_io do
      @cli.send(:display_result, result: Master::Result.err("interrupted", category: :abort), accumulated: "", streamed: false)
    end

    assert_empty out
  end

  # A late cursor-position reply was saved as "[38;51Rh" and replayed each boot.
  def test_terminal_replies_never_reach_the_transcript
    Reline.stub(:readline, "[38;51Rhi\e[38;51R") do
      Reline::IOGate.stub(:in_pasting?, false) do
        assert_equal "hi", @cli.send(:safe_read_line, "% ")
      end
    end
  end

  def test_a_paste_arrives_as_one_message
    lines = %w[second third]
    Reline.stub(:readline, ->(*) { lines.shift || "first" }) do
      Reline::IOGate.stub(:in_pasting?, -> { !lines.empty? }) do
        lines.unshift("first")
        assert_equal "first\nsecond\nthird", @cli.send(:safe_read_line, "% ")
      end
    end
  end

  def test_the_boot_scan_names_the_command_that_repairs_what_it_found
    summary = Struct.new(:violation_count, :rule_count).new(1604, 148)

    assert_equal "scan0: lib/ 1604 violations, 148 rules; /fix lib repairs them", @cli.send(:boot_scan_line, summary)
  end

  def test_an_empty_line_runs_nothing
    @cli.stub(:run_input, ->(*) { flunk "an empty line ran a turn" }) do
      assert_nil @cli.send(:handle_repl_line, "")
    end
  end

  def test_an_empty_success_is_an_error_instead_of_silence
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, mode:| "#{mode}: #{text}" }
    cli = Master::CLI::Session.new(container: @container.merge(renderer:))

    out, = capture_io do
      cli.send(:display_result, result: Master::Result.ok(rendered: "", output: ""), accumulated: "", streamed: false)
    end

    assert_match(/err0: turn completed without output/, out)
    assert_match(/err0: result=Hash/, out)
    assert_equal 2, cli.exit_code
  end

  def test_units_console_footers_receive_the_result_not_the_success_boolean
    result = Master::Result.ok(rendered: "", output: {})
    seen = []

    @cli.stub(:print_fix_activity_footer, nil) do
      @cli.stub(:print_previous_question_footer, nil) do
        @cli.stub(:print_parallel_errors_footer, ->(value) { seen << [:parallel, value] }) do
          @cli.stub(:print_capability_stamp, ->(value) { seen << [:capability, value] }) do
            capture_io do
              @cli.send(:display_ok, ok: result, accumulated: +"", streamed: false, units_console: true)
            end
          end
        end
      end
    end

    assert_equal [[:parallel, result], [:capability, result]], seen
  end

  def test_pipeline_context_success_renders_its_fields_not_object_identity
    context = Master::CLI::PipelineContext.new(
      user_message: "status", output: "raw command output", rendered: "human-readable command output"
    )
    result = Master::Result.ok(context)

    assert_equal "human-readable command output", @cli.send(:success_text, result)
    assert_equal "raw command output", @cli.send(:raw_success_text, result)
  end

  def test_routine_success_emits_one_line
    result = Master::Result.ok(output: "saved")

    out, = capture_io { @cli.send(:display_ok, ok: result, accumulated: +"", streamed: false) }

    assert_equal "saved\n", out
  end

  # The state line's meaning is model, violations and error. Git drifts with
  # every save, the phase with every stage, the token count with every turn —
  # "main dirty llm discover, grok-cli:auto, 270/128.0k" repainted between
  # prompts with nothing new to say (Johann's log 2026-11-08). The prompt
  # below it already carries git and phase live.
  def test_the_state_line_meaning_ignores_git_phase_and_token_drift
    live = "main dirty llm discover, grok-cli:auto, 260/128.0k"
    drifted = "main ahead 1 dirty llm model, grok-cli:auto, 270/128.0k"
    errored = "main dirty llm error, grok-cli:auto, 270/128.0k"
    other_lane = "main dirty llm discover, glyph-cluster, 260/128.0k"
    violating = "main dirty llm discover, grok-cli:auto, 260/128.0k, 2 violations"

    assert @cli.send(:same_state_meaning?, drifted, live)
    refute @cli.send(:same_state_meaning?, errored, live), "the error word is news"
    refute @cli.send(:same_state_meaning?, other_lane, live), "a lane change is news"
    refute @cli.send(:same_state_meaning?, violating, live), "violations are news"
  end

  # The stream prints every chunk as it arrives; the display closes the row
  # instead of printing the accumulated buffer again. The old re-print put a
  # second copy on the same row: "Grok 4.7, from xAI.Grok 4.7, from xAI."
  # (Johann's log 2026-11-08).
  def test_a_streamed_reply_is_not_printed_twice
    result = Master::Result.ok(output: "Grok 4.7, from xAI.")

    out, = capture_io do
      @cli.send(:display_ok, ok: result, accumulated: +"Grok 4.7, from xAI.", streamed: true)
    end

    assert_equal "\n", out
  end

  # A streamed turn whose final answer arrived after the stream stopped (the
  # next lane, a tool loop's last reply) still prints the answer. The
  # duplicate check reads the raw output: the rendered form wears ANSI
  # escapes the stream never showed, and one escaped prefix read as "not yet
  # printed" — the reply then appeared twice.
  def test_an_unstreamed_final_answer_still_prints_once
    result = Master::Result.ok(output: "the tool loop's final word")
    @renderer.expect(:measure, "the tool loop's final word\n", [String], width: Integer)

    out, = capture_io do
      @cli.send(:display_ok, ok: result, accumulated: +"the streamed lead-up", streamed: true)
    end

    assert_includes out, "the tool loop's final word"
    refute_includes out, "the streamed lead-upthe tool loop"
  end

  def test_pipe_dispatches_slash_commands
    @cli.define_singleton_method(:handle_repl_line) { |line| @piped_command = line }

    @cli.pipe("/self\n")

    assert_equal "/self", @cli.instance_variable_get(:@piped_command)
  end

  def test_self_scan_uses_container_dependencies
    scanner = Object.new
    bus = Object.new
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, mode:| "#{mode}:#{text}" }
    cli = Master::CLI::Session.new(container: @container.merge(config: {}, scanner:, bus:, renderer:, root: "/tmp/master"))
    summary = Struct.new(:violation_count, :line).new(1, "judge: lib/ 1 rules, 1 violations")
    scan = Minitest::Mock.new
    scan.expect(:call, Master::Result.ok(summary), stream: true, autofix: true)

    Master::Review::Scan::SelfScan.stub(:new, ->(scanner:, root:, event_bus:) {
      assert_same scanner, cli.container[:scanner]
      assert_equal "/tmp/master", root
      assert_same bus, event_bus
      scan
    }) do
      out, = capture_io { cli.send(:run_self_scan) }
      assert_equal "scan0: judge: lib/ 1 rules, 1 violations\n", out
    end
    scan.verify
  end

  # Dispatch. `handle_repl_line` (lib/cli/session/repl_flow.rb) dispatches slash
  # commands and sends everything else to `run_agent_turn`; `process`/`pipe`
  # reach a turn through `TurnRouter.call`, not `container[:pipeline]`. `/tts`
  # lives on the web face (`/chat/tts`), so nothing here asserts a CLI TTS flag.

  def test_plain_text_line_is_sent_as_a_turn_not_treated_as_a_command
    seen = :unset
    @cli.stub(:run_input, ->(line) { seen = line }) do
      @cli.send(:handle_repl_line, "hello world")
    end
    assert_equal "hello world", seen
  end

  # A line shaped like "/word" is a command request, not prose. The REPL
  # refuses a word it does not know instead of spending a 60-90 second model
  # turn on it (Johann's log 2026-11-08: a typo queued, spun, and came back
  # as the model's apology for a surface it does not own).
  def test_unknown_slash_command_is_refused_without_a_model_turn
    seen = :unset
    @renderer.expect(:render, "err0: unknown command: /foo\n", [String], mode: :error)
    out, = capture_io do
      @cli.stub(:run_input, ->(_line) { seen = _line }) do
        @cli.send(:handle_repl_line, "/foo")
      end
    end
    assert_equal :unset, seen, "a typo'd command must not cost a model turn"
    assert_match(/unknown command: \/foo/, out)
    @renderer.verify
  end

  def test_unknown_slash_command_suggests_the_closest_verb
    @renderer.expect(:render, "err0: unknown command: /stauts - did you mean /status?\n", [String], mode: :error)
    out, = capture_io { @cli.send(:handle_repl_line, "/stauts") }
    assert_match(/did you mean \/status\?/, out)
    @renderer.verify
  end

  # One name table for both doors: the pipeline's spelling resolves to the
  # verb it names, so /tts answers with /voice's behaviour at the REPL too.
  def test_tts_spelling_dispatches_the_voice_command
    called = nil
    @container[:commands] = { "voice" => ->(args:) { called = args; "" } }
    capture_io { @cli.send(:handle_repl_line, "/tts off") }
    assert_equal "off", called
  end

  # Johann's log 2026-11-08: /voice and /help typed during an 89-second turn
  # queued four to six deep, so the operator toggled session sound for a
  # conversation that had already moved on. Local-state verbs run at once;
  # everything else keeps its place in the queue.
  def test_turn_safe_slash_command_runs_while_a_turn_streams
    worker = Thread.new { sleep 5 }
    @cli.instance_variable_set(:@turn_worker, worker)
    called = nil
    @container[:commands] = { "status" => ->(args:) { called = args; "" } }
    capture_io { @cli.send(:handle_repl_line, "/status") }
    assert_equal "", called, "a turn-safe verb answers now, not behind the running turn"
    assert_empty @cli.instance_variable_get(:@turn_queue)
  ensure
    worker.kill
  end

  def test_writing_slash_command_still_queues_behind_a_running_turn
    worker = Thread.new { sleep 5 }
    @cli.instance_variable_set(:@turn_worker, worker)
    called = nil
    @container[:commands] = { "play" => ->(args:) { called = args; "" } }
    capture_io { @cli.send(:handle_repl_line, "/play one") }
    assert_nil called, "a writing verb must not interleave with the running turn"
    assert_equal ["/play one"], @cli.instance_variable_get(:@turn_queue)
  ensure
    worker.kill
  end

  def test_exit_still_closes_when_session_save_fails
    Dir.mktmpdir do |root|
      cli = Master::CLI::Session.new(container: @container.merge(config: {}, root:))
      cli.instance_variable_set(:@running, true)

      @session.expect(:save!, nil) { raise JSON::GeneratorError, "invalid UTF-8" }
      @renderer.expect(:closing, "master0: closed")

      out, err = capture_io { cli.send(:handle_repl_line, "/exit") }

      assert_match(/session0: save failed - JSON::GeneratorError: invalid UTF-8/, out + err)
      assert_equal "master0: closed\n", out
      refute cli.instance_variable_get(:@running)
      @renderer.verify
      @session.verify
    end
  end

  def test_close_session_is_idempotent
    Dir.mktmpdir do |root|
      cli = Master::CLI::Session.new(container: @container.merge(config: {}, root:))
      @session.expect(:save!, nil)

      cli.send(:close_session)
      cli.send(:close_session)

      @session.verify
    end
  end

  def test_exit_saves_the_session_and_stops_the_repl
    Dir.mktmpdir do |root|
      cli = Master::CLI::Session.new(container: @container.merge(config: {}, root:))
      cli.instance_variable_set(:@running, true)
      @session.expect(:save!, nil)
      @renderer.expect(:closing, nil)

      capture_io { cli.send(:handle_repl_line, "/exit") }

      refute cli.instance_variable_get(:@running), "/exit must stop the repl loop"
      @session.verify
      @renderer.verify
    end
  end

  def test_blank_input_publishes_empty_input_instead_of_running_a_turn
    bus = Minitest::Mock.new
    bus.expect(:publish, nil, ["cli:empty_input"], source: :run_input)
    cli = Master::CLI::Session.new(container: @container.merge(config: {}, bus:))

    assert_nil cli.run_input("   ")
    bus.verify
  end

  def test_pipe_dispatches_through_the_repl_line_handler
    seen = :unset
    @cli.stub(:handle_repl_line, ->(line) { seen = line; :handled }) do
      assert_equal :handled, @cli.pipe("  ping  ")
    end
    assert_equal "ping", seen, "pipe strips before dispatching"
  end

  def test_display_result_records_ok_and_err_for_the_exit_code
    root = Dir.mktmpdir # not a git checkout, so the changed-files footer stays quiet
    cli = Master::CLI::Session.new(container: @container.merge(config: {}, root:))
    @session.expect(:cost, 0.0)
    @session.expect(:tokens_billed, 0)

    capture_io { cli.send(:display_result, result: Master::Result.ok(rendered: "42"), accumulated: "42", streamed: true) }
    assert cli.instance_variable_get(:@last_ok)
    assert_equal 0, cli.instance_variable_get(:@exit_code)

    @renderer.expect(:render, "[ERR]", [String], mode: :error)
    capture_io { cli.send(:display_result, result: Master::Result.err("model unavailable"), accumulated: "", streamed: false) }
    refute cli.instance_variable_get(:@last_ok)
    refute_equal 0, cli.instance_variable_get(:@exit_code)
  end
  def test_active_fold_cancellation_is_cooperative
    token = Master::Core::CancellationToken.new.activate!
    @cli.instance_variable_set(:@turn_cancellation, token)
    @cli.define_singleton_method(:cancel_turn) do |*|
      flunk("active Fold turns must stop at a safe boundary, not be killed")
    end

    @cli.send(:request_or_interrupt_turn, Object.new, nil, reason: "ctrl_c")

    assert_predicate token, :cancelled?
    assert_match(/Ctrl-C/, token.reason)
  end

  def test_non_fold_cancellation_uses_existing_interrupt_fallback
    token = Master::Core::CancellationToken.new
    @cli.instance_variable_set(:@turn_cancellation, token)
    turn = Object.new
    children = Object.new
    called = nil
    @cli.define_singleton_method(:cancel_turn) { |actual_turn, actual_children| called = [actual_turn, actual_children] }

    @cli.send(:request_or_interrupt_turn, turn, children, reason: "ctrl_c")

    assert_equal [turn, children], called
    assert_predicate token, :cancelled?
  end

  def test_dispatch_stop_race_uses_cooperative_policy_for_fold_work
    requested = nil
    spawn = lambda do |_input, on_turn:, on_chunk:, cancellation:|
      cancellation.activate!
      @cli.instance_variable_set(:@turn_cancel_requested, true)
      Thread.new { Master::Result.ok("finished") }
    end
    request_stop = lambda do |turn, children, reason:|
      requested = [turn, children, reason]
      @cli.instance_variable_get(:@turn_cancellation).cancel!(reason:)
    end

    @cli.stub(:spawn_pipeline_thread, spawn) do
      @cli.stub(:request_or_interrupt_turn, request_stop) do
        @cli.stub(:fetch_pipeline_result, -> { Master::Result.ok("finished") }) do
          result = @cli.send(:dispatch_turn, "do work", accumulated: +"", state: {})
          assert result.ok?
        end
      end
    end

    assert_equal "stop", requested[2]
    assert_predicate @cli.instance_variable_get(:@turn_cancellation), :cancelled?
  end

  def test_help_is_dispatched_immediately_while_a_turn_is_busy
    worker = Object.new
    worker.define_singleton_method(:alive?) { true }
    @cli.instance_variable_set(:@turn_worker, worker)
    seen = nil

    @cli.stub(:run_help, ->(topic) { seen = topic; :shown }) do
      assert_equal :shown, @cli.send(:handle_repl_line, "/help voice")
    end

    assert_equal "voice", seen
    assert_empty @cli.instance_variable_get(:@turn_queue)
  end

  def test_model_selector_is_dispatched_immediately_while_a_turn_is_busy
    worker = Object.new
    worker.define_singleton_method(:alive?) { true }
    @cli.instance_variable_set(:@turn_worker, worker)
    seen = nil

    @cli.stub(:dispatch_registered_slash_command, ->(command) { seen = command; :dispatched }) do
      assert_equal :dispatched, @cli.send(:handle_repl_line, "/model")
    end

    assert_equal "/model", seen
    assert_empty @cli.instance_variable_get(:@turn_queue)
  end

  def test_voice_controls_are_dispatched_immediately_while_a_turn_is_busy
    worker = Object.new
    worker.define_singleton_method(:alive?) { true }
    @cli.instance_variable_set(:@turn_worker, worker)
    seen = nil

    @cli.stub(:dispatch_registered_slash_command, ->(command) { seen = command; :dispatched }) do
      assert_equal :dispatched, @cli.send(:handle_repl_line, "/voice off")
    end

    assert_equal "/voice off", seen
    assert_empty @cli.instance_variable_get(:@turn_queue)
  end

  def test_tts_spelling_reaches_voice_command_while_a_turn_is_busy
    worker = Object.new
    worker.define_singleton_method(:alive?) { true }
    @cli.instance_variable_set(:@turn_worker, worker)
    seen = nil

    @cli.stub(:dispatch_registered_slash_command, ->(command) { seen = command; :dispatched }) do
      assert_equal :dispatched, @cli.send(:handle_repl_line, "/tts off")
    end

    assert_equal "/voice off", seen
    assert_empty @cli.instance_variable_get(:@turn_queue)
  end

  def test_directory_change_waits_until_the_active_turn_finishes
    worker = Object.new
    worker.define_singleton_method(:alive?) { true }
    @cli.instance_variable_set(:@turn_worker, worker)
    queued = nil

    @cli.stub(:enqueue_interactive_line, ->(line) { queued = line; true }) do
      @cli.send(:handle_repl_line, "cd ..")
    end

    assert_equal "cd ..", queued
  end

  # Johann's log 2026-11-08: "queue0: worker failed - NoMethodError: undefined
  # method 'value' for true", twice in one session. A queued turn whose reply
  # had already reached the operator through the units console displayed through
  # display_units_console_turn, which handed the ok bookkeeping boolean where
  # the turn's Result belongs; print_parallel_errors_footer then called .value
  # on true. The reproduction runs the queue boundary for real: enqueue while a
  # worker is busy, drain, and each turn completes through the units console.
  def test_a_units_console_turn_off_the_queue_reports_no_worker_failure
    worker = Object.new
    worker.define_singleton_method(:alive?) { true }
    @cli.instance_variable_set(:@turn_worker, worker)

    out, err = capture_io { run_units_console_turns_off_the_queue(%w[summarise what changed and what broke]) }

    refute_match(/worker failed/, out + err)
    refute_match(/undefined method 'value' for true/, out + err)
    assert_empty @cli.instance_variable_get(:@turn_queue), "the queue drained despite the display"
  end

  def run_units_console_turns_off_the_queue(lines)
    units_turn = lambda do |_input, accumulated:, state:|
      state[:units_console] = true
      Master::Result.ok(nil)
    end

    @cli.stub(:check_budget_blocks, nil) do
      @cli.stub(:dispatch_turn, units_turn) do
        @cli.stub(:handle_repl_line, ->(line) { @cli.send(:run_input, line) }) do
          lines.each { |line| assert @cli.send(:enqueue_interactive_line, line) }
          @cli.send(:drain_interactive_queue)
        end
      end
    end
  end

  # The footers still work: with the Result in hand, a parallel error rides to
  # the operator, which is what the footer exists for.
  def test_the_units_console_footers_read_the_turn_result
    ok = Master::Result.ok({_parallel_errors: ["lane x: timeout"], _stage_error: ""})

    out, = capture_io do
      @cli.instance_variable_set(:@last_ok, true)
      @cli.send(:display_units_console_turn, ok)
    end

    assert_match(/parallel0: lane x: timeout/, out)
  end

  # The transcript read "err: zsh: timed out after 30s" as a failure and asked
  # again; /help now names the cap, and the number is the Shell's own constant.
  def test_help_names_the_governed_shell_cap
    summary = Master::CLI::CommandRegistry.help_text

    assert_includes summary, "capped at #{Integer(Master::Io::Shell::TIMEOUT)}s"
    assert_includes summary, "is the cap, not a failure"
  end

  # bin/master's fast one-shot queued the turn and left before the worker ran
  # it: no answer reached the operator and the exit code was always 0. The
  # drain joins the worker for real, and the exit code is the turn's own.
  def test_draining_pending_turns_runs_the_queue_and_reports_the_turn_outcome
    @cli.stub(:check_budget_blocks, nil) do
      @cli.stub(:dispatch_turn, ->(_input, accumulated:, state:) { Master::Result.ok("drained reply") }) do
        out, = capture_io do
          assert @cli.send(:enqueue_interactive_line, "first queued line")
          assert @cli.send(:enqueue_interactive_line, "second queued line")
          assert_equal 0, @cli.drain_pending_turns!
        end

        assert_match(/drained reply/, out, "the queued turn's reply reached the operator")
      end
    end
    assert_empty @cli.instance_variable_get(:@turn_queue)
    assert_nil @cli.instance_variable_get(:@turn_worker)
  end

  def test_draining_with_no_pending_turns_answers_at_once
    assert_equal 0, @cli.drain_pending_turns!
  end

end
