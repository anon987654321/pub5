# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/kernel"
require "tmpdir"
require "open3"
require "digest"
require "json"
require "time"

# Every command the registry builds must be able to run, and the built surface,
# the help pages and the module's tables must describe one set of verbs.
#
# Command#call ends in `@receiver.public_send(@method_name, ...)`, so a symbol
# that names no public method fails when a person types the verb rather than
# when the registry is built. The command tables that `build` never merged are
# deleted; the third test keeps a new one from arriving unmerged.
class TestCommandRegistryDispatch < Minitest::Test
  Registry = Master::CLI::CommandRegistry

  class BacklogReviewKernel
    attr_reader :events

    def initialize(events = [])
      @events = events
    end

    def verify_log! = @events

    # The real Kernel writes JSON and reads rows back, so a payload's symbol
    # keys become strings. Storing the raw hash made every string-keyed
    # assertion here read nil while production was correct.
    def append_event(kind, payload, run_id: nil)
      row = { "kind" => kind, "payload" => JSON.parse(JSON.generate(payload)),
              "run_id" => run_id, "at" => Time.now.utc.iso8601(6) }
      @events << row
      row
    end
  end

  class BacklogReviewAgent
    attr_reader :prompts, :operations

    def initialize(answer)
      @answer = answer
      @prompts = []
      @operations = []
    end

    def ask(prompt, operation:)
      @prompts << prompt
      @operations << operation
      @answer.respond_to?(:call) ? @answer.call(prompt) : @answer
    end
  end

  def with_backlog_repo
    Dir.mktmpdir("fix-weekly-backlog") do |root|
      todo = "# Remaining work\n- [ ] **Review the runner** Inspect runner changes and execute focused tests.\n"
      File.write(File.join(root, "TODO.md"), todo)
      File.write(File.join(root, "runner.rb"), "RUNNER_VERSION = 1\n")
      [
        ["git", "init", "-q"],
        ["git", "config", "user.name", "Backlog Review Test"],
        ["git", "config", "user.email", "backlog-review@example.invalid"],
        ["git", "add", "TODO.md", "runner.rb"],
        ["git", "commit", "-q", "-m", "update runner implementation"],
      ].each do |argv|
        _output, status = Open3.capture2e(*argv, chdir: root)
        assert status.success?, "test repository command failed: #{argv.join(" ")}"
      end
      yield root, todo
    end
  end

  def test_weekly_backlog_review_is_not_due_before_seven_days
    now = Time.utc(2026, 11, 6, 12)
    previous = { "kind" => "backlog_review_completed",
                 "at" => (now - Registry::BACKLOG_REVIEW_INTERVAL + 1).iso8601 }
    kernel = BacklogReviewKernel.new([previous])
    agent = BacklogReviewAgent.new(->(*) { flunk "not-due review must not call the model" })
    result = Registry.weekly_backlog_review(
      deliberation: Struct.new(:agent).new(agent), bus: nil, repo_root: "/unused", kernel:, now:
    )

    assert_equal :not_due, result
    assert_equal [previous], kernel.events
    assert_empty agent.prompts
  end

  def test_weekly_backlog_review_records_validated_candidates_without_editing_todo
    with_backlog_repo do |root, todo|
      head, status = Open3.capture2e("git", "rev-parse", "HEAD", chdir: root)
      assert status.success?
      line = todo.lines.find_index { |value| value.start_with?("- [ ]") } + 1
      id = Digest::SHA256.hexdigest("#{line}:#{todo.lines.fetch(line - 1).strip}")[0, 12]
      agent = BacklogReviewAgent.new(JSON.generate(
        "summary" => "A recent runner change may overlap this item; focused test execution remains required.",
        "completion_candidates" => [{ "id" => id, "commit" => head.strip,
                                      "reason" => "The commit updates runner.rb; run focused tests before closure." }],
        "stale_candidates" => [],
      ))
      kernel = BacklogReviewKernel.new
      result = Registry.weekly_backlog_review(
        deliberation: Struct.new(:agent).new(agent), bus: nil, repo_root: root, kernel:, now: Time.now
      )

      assert_equal :reviewed, result
      event = kernel.events.last
      assert_equal "backlog_review_completed", event.fetch("kind")
      assert_equal 1, event.dig("payload", "open_item_count")
      assert_equal id, event.dig("payload", "completion_candidates", 0, "id")
      assert_equal head.strip, event.dig("payload", "completion_candidates", 0, "commit")
      assert_equal :structural_review, agent.operations.first
      assert_includes agent.prompts.first, todo
      assert_equal todo, File.read(File.join(root, "TODO.md"))
    end
  end

  def test_invalid_review_response_is_inconclusive_and_leaves_review_due
    with_backlog_repo do |root, _todo|
      kernel = BacklogReviewKernel.new
      result = Registry.weekly_backlog_review(
        deliberation: Struct.new(:agent).new(BacklogReviewAgent.new("not JSON")),
        bus: nil, repo_root: root, kernel:, now: Time.now
      )

      assert_equal :inconclusive, result
      assert_equal "backlog_review_inconclusive", kernel.events.last.fetch("kind")
      refute kernel.events.any? { |row| row["kind"] == "backlog_review_completed" }
    end
  end

  def test_an_inconclusive_attempt_does_not_reset_the_weekly_interval
    now = Time.utc(2026, 11, 6, 12)
    attempt = { "kind" => "backlog_review_inconclusive", "at" => now.iso8601 }
    kernel = BacklogReviewKernel.new([attempt])
    result = Registry.weekly_backlog_review(
      deliberation: nil, bus: nil, repo_root: "/unused", kernel:, now:
    )

    assert_equal :inconclusive, result
    assert_equal [attempt], kernel.events
  end

  def test_read_only_weekly_review_does_not_write_a_kernel_receipt
    with_backlog_repo do |root, todo|
      head, status = Open3.capture2e("git", "rev-parse", "HEAD", chdir: root)
      assert status.success?
      kernel = BacklogReviewKernel.new
      answer = JSON.generate("summary" => "No item can be closed without execution proof.",
                             "completion_candidates" => [], "stale_candidates" => [])
      result = Registry.weekly_backlog_review(
        deliberation: Struct.new(:agent).new(BacklogReviewAgent.new(answer)),
        bus: nil, repo_root: root, kernel:, now: Time.now, record: false
      )

      assert_equal :reviewed, result
      assert_empty kernel.events
      assert_equal todo, File.read(File.join(root, "TODO.md"))
    end
  end

  def test_success_receipt_survives_a_new_kernel_instance
    Dir.mktmpdir("fix-backlog-restart") do |root|
      Dir.mkdir(File.join(root, ".git"))
      first = Master::Fix::Kernel.new(root:, actor: "backlog-review-test")
      first.append_event("backlog_review_completed", { schema: 1, status: "reviewed" })
      now = Time.now.utc
      restarted = Master::Fix::Kernel.new(root:, actor: "backlog-review-restart")

      result = Registry.weekly_backlog_review(
        deliberation: nil, bus: nil, repo_root: root, kernel: restarted, now:
      )

      assert_equal :not_due, result
      assert_equal "backlog_review_completed", restarted.verify_log!.last.fetch("kind")
    end
  end

  def built
    @built ||= Registry.build(
      infra: { session: Master::Trace::Session.new, config: {}, root: Master::ROOT, bus: nil },
      ai: { agent: nil },
      root: Master::ROOT,
    )
  end

  def test_every_built_command_names_a_public_method
    unresolvable = built.filter_map do |verb, command|
      name = command.method_name
      "/#{verb} -> #{name}" unless name.nil? || Registry.respond_to?(name)
    end

    assert_operator built.size, :>=, 10, "a registry this small means build broke, not that the surface shrank"
    assert_empty unresolvable, "these verbs dispatch to a method nothing answers: #{unresolvable.join(', ')}"
  end

  # A verb with no page is a command nobody can find, and a page with no verb
  # sends the reader to type something the router cannot resolve.
  def test_help_pages_and_the_built_surface_are_one_set
    assert_equal built.keys.sort, Registry::HELP_TOPICS.keys.sort
  end
  def test_help_overview_leads_with_plain_language_and_lists_every_registered_command
    summary = Registry.help_summary

    assert_match(/\Ainput0 at master0: describe work in plain language/, summary)
    assert_includes summary, "try0 at master0:"
    assert_includes summary, "keys0 at master0: Tab suggests common commands"
    assert_includes summary, "multi0 at master0: << starts multiline"
    assert_includes summary, "fix0 at master0: /fix [path]"
    Registry::HELP_TOPICS.each_key { |name| assert_includes summary, "/#{name}" }
    assert_includes summary, "/exit"
    assert_includes summary, "/quit"
    assert_includes summary, "/help [command]"
  end

  def test_help_overview_wraps_long_command_groups
    summary = Registry.help_summary
    session_lines = summary.lines.grep(/\A(?:session0 at master0:|  )/)

    assert_operator session_lines.length, :>=, 2
    assert session_lines.all? { |line| line.chomp.length <= 76 }, "session help should not become a wide command ribbon"
    Registry::HELP_TOPICS.each_key { |name| assert_includes summary, "/#{name}" }
  end

  def test_command_surface_and_help_list_stay_in_parity
    surface = Registry.command_surface.map { |entry| entry.fetch(:cmd) }.sort
    assert_equal Registry.slash_commands.sort, surface
  end

  def test_help_resolves_exit_aliases_and_normalizes_case
    assert_match(%r{\A/exit - }, Registry.help_text("exit"))
    assert_match(%r{\A/quit - }, Registry.help_text("/quit"))
    assert_equal Registry.help_text("fix"), Registry.help_text("Fix")
  end

  def test_help_resolves_route_aliases_to_the_canonical_topic
    assert_equal Registry.help_text("voice"), Registry.help_text("tts")
    assert_equal Registry.help_text("reload"), Registry.help_text("restart")
  end

  def test_help_suggests_a_nearby_command_without_executing_it
    assert_includes Registry.help_text("statuz"), "did you mean /status?"
    assert_includes Registry.help_text("zzzzzzzz"), "/help lists the surface"
  end

  def test_every_public_help_topic_has_a_summary_and_detail_list
    Registry::HELP_TOPICS.each do |name, topic|
      refute_empty topic.fetch(:summary).to_s, "#{name} needs a useful summary"
      assert_instance_of Array, topic.fetch(:detail), "#{name} needs a detail list"
    end
  end

  def test_command_categories_are_shared_with_the_web_surface
    surface = Registry.command_surface
    assert_equal "fix", surface.find { |entry| entry[:cmd] == "/fix" }.fetch(:category)
    assert_equal "review", surface.find { |entry| entry[:cmd] == "/laws" }.fetch(:category)
    assert_equal "session", surface.find { |entry| entry[:cmd] == "/quit" }.fetch(:category)
    assert_includes Registry.help_summary, "fix0 at master0: /fix [path]"
    assert_includes Registry.help_summary, "help0 at master0: /help [command]"
    assert_includes Registry.help_summary, "/exit /quit"
    assert_includes Registry.help_summary, "input0 at master0: describe work in plain language; slash commands are optional."
    # The overview names the fix unit once: the fix category line is the only
    # "/fix [path]", and the second copy the old footer appended read as a
    # repeated device probe (Johann's log 2026-11-08, /help twice naming fix0).
    assert_equal 1, Registry.help_summary.lines.count { |line| line.include?("fix0 at master0") }
  end

  def test_reload_help_names_plain_language_restart_phrases
    help = Registry.help_text("reload")

    assert_includes help, "/reload"
    assert_includes help, "restart MASTER"
    assert_includes help, "reload yourself"
  end

  def test_task_and_capability_commands_are_registered_and_documented
    assert_equal :dispatch_task, built.fetch("task").method_name
    assert_equal :dispatch_capabilities, built.fetch("capabilities").method_name
    assert_includes Registry.help_text("task"), "/task verify-step"
    assert_includes Registry.help_text("capabilities"), "/capabilities describe"
  end

  def test_nsfw_command_requires_local_opt_in_and_passes_an_nsfw_task
    previous = %w[MASTER_NSFW MASTER_NSFW_MODEL MASTER_NO_OLLAMA].to_h { |key| [key, ENV[key]] }
    previous_visitor = Fiber[:master_visitor]
    ENV["MASTER_NSFW"] = "1"
    ENV["MASTER_NSFW_MODEL"] = "dolphin3:8b"
    ENV.delete("MASTER_NO_OLLAMA")
    Fiber[:master_visitor] = nil
    received = nil
    agent = Object.new
    agent.define_singleton_method(:call) { |context| received = context; :handled }

    result = Registry.dispatch_nsfw(agent, ctx: { args: "write an adult romance" })

    assert_equal :handled, result
    assert_equal "nsfw", received.fetch(:task_type)
    assert_equal "write an adult romance", received.fetch(:message)

    ENV["MASTER_NO_OLLAMA"] = "1"
    blocked = Registry.dispatch_nsfw(agent, ctx: { args: "write an adult romance" })
    assert_instance_of Master::Result::Err, blocked
    assert_equal :policy, blocked.category

    Fiber[:master_visitor] = true
    ENV.delete("MASTER_NO_OLLAMA")
    visitor = Registry.dispatch_nsfw(agent, ctx: { args: "write an adult romance" })
    assert_instance_of Master::Result::Err, visitor
    assert_equal :policy, visitor.category
  ensure
    previous&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Fiber[:master_visitor] = previous_visitor
  end

  def test_skill_review_command_approves_and_revokes_only_the_exact_revision
    require "tmpdir"
    old_visitor = Fiber[:master_visitor]
    Fiber[:master_visitor] = nil

    Dir.mktmpdir("skill-review-command") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      # Approval reads each fixture first; a registry skill keeps them in test/fixtures/skills.
      fixtures = File.join(root, "test", "fixtures", "skills")
      FileUtils.mkdir_p(fixtures)
      File.write(File.join(fixtures, "release.yml"), "expect: bounded release verification\n")
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        skills_registry:
          skills:
            - name: release-skill
              description: audited capability
              triggers: ["release phrase"]
              body: "Execute a bounded release verification."
              execution_contract:
                schema_version: 1
                version: "1.0.0"
                status: candidate
                risk: medium
                required_capabilities: [read]
                laws: [ROBUSTNESS]
                fixtures: [release.yml]
      YAML
      approval_path = File.join(root, "operator", "skill_approvals.yml")
      unapproved = Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!).find("release-skill")
      revision = unapproved.fetch(:revision)
      refute_predicate unapproved.fetch(:contract), :permitted_for_trigger?

      listed = Registry.dispatch_skill(root, ctx: { args: "list" }, approval_path:)
      assert_includes listed, "release-skill"
      assert_includes listed, revision
      assert_includes Registry.help_text("skill"), "/skill approve NAME SHA256 --confirm"

      visitor_denial = nil
      Fiber[:master_visitor] = true
      visitor_denial = Registry.dispatch_skill(
        root, ctx: { args: "approve release-skill #{revision} --confirm" }, approval_path:
      )
      assert_match(/local operator only/, visitor_denial)
      refute File.exist?(approval_path)
      Fiber[:master_visitor] = nil

      missing_confirmation = Registry.dispatch_skill(
        root, ctx: { args: "approve release-skill #{revision}" }, approval_path:
      )
      assert_match(/--confirm/, missing_confirmation)
      refute File.exist?(approval_path)

      approved = Registry.dispatch_skill(
        root, ctx: { args: "approve release-skill #{revision} --confirm" }, approval_path:
      )
      assert_match(/approved release-skill revision=#{revision}/, approved)
      assert_equal 0o600, File.stat(approval_path).mode & 0o777
      active = Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!)
      assert_equal ["release-skill"], active.trigger_for("please use release phrase").map { |row| row[:name] }

      stale_revision = "0" * 64
      mismatch = Registry.dispatch_skill(
        root, ctx: { args: "approve release-skill #{stale_revision} --confirm" }, approval_path:
      )
      assert_match(/revision mismatch/, mismatch)
      # A refused approval changes nothing: the exact revision approved above still stands.
      still = Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!).trigger_for("release phrase")
      assert_equal ["release-skill"], still.map { |row| row[:name] }

      revoked = Registry.dispatch_skill(
        root, ctx: { args: "revoke release-skill #{revision} --confirm" }, approval_path:
      )
      assert_match(/revoked release-skill revision=#{revision}/, revoked)
      refute_includes Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!).trigger_for("release phrase").map { |row| row[:name] }, "release-skill"
    end
  ensure
    Fiber[:master_visitor] = old_visitor
  end

  def test_capability_inventory_is_restricted_for_visitors
    old_visitor = Fiber[:master_visitor]
    Fiber[:master_visitor] = true
    assert_match(/local operator only/, Registry.dispatch_capabilities(Master::ROOT, ctx: { args: "list" }))
  ensure
    Fiber[:master_visitor] = old_visitor
  end

  def test_task_cli_and_capability_search_are_actionable
    require "tmpdir"
    old_subject = Fiber[:master_pair_subject]
    old_visitor = Fiber[:master_visitor]
    Fiber[:master_pair_subject] = nil
    Fiber[:master_visitor] = nil

    Dir.mktmpdir("task-cli") do |root|
      created = Registry.dispatch_task(root, ctx: { args: 'create "Call the dentist"' })
      assert_match(/created [a-f0-9]+ \[open\] Call the dentist/, created)
      listed = Registry.dispatch_task(root, ctx: { args: "list" })
      assert_includes listed, "Call the dentist"
      assert_includes listed, "no background notifications are sent"
      described = Registry.dispatch_capabilities(Master::ROOT, ctx: { args: "search browser" })
      assert_match(/core_tool Browser|plugin session_browser/, described)
    end
  ensure
    Fiber[:master_pair_subject] = old_subject
    Fiber[:master_visitor] = old_visitor
  end

  def test_guest_pair_management_is_denied
    old_visitor = Fiber[:master_visitor]
    Fiber[:master_visitor] = true
    assert_match(/local-only/, Registry.dispatch_pair(Master::ROOT, ctx: { args: "issue" }))
    assert_match(/local-only/, Registry.dispatch_pair(Master::ROOT, ctx: { args: "list" }))
  ensure
    Fiber[:master_visitor] = old_visitor
  end

  def test_mobile_platform_commands_replace_the_public_device_surface
    assert_equal :dispatch_android, built.fetch("android").method_name
    assert_equal :dispatch_ios, built.fetch("ios").method_name
    assert_equal :dispatch_pair, built.fetch("pair").method_name
    %w[device owner].each { |gone| refute built.key?(gone), "/#{gone} is replaced by /android or /ios" }
    assert Registry.respond_to?(:dispatch_device)
  end

  def test_privacy_grant_is_local_only_subject_scoped_and_revocable
    require "tmpdir"
    old_subject = Fiber[:master_pair_subject]
    old_paired = Fiber[:master_paired]
    old_visitor = Fiber[:master_visitor]

    Dir.mktmpdir("privacy-command") do |root|
      Fiber[:master_pair_subject] = "subject-a"
      Fiber[:master_paired] = true
      Fiber[:master_visitor] = nil

      grant = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/privacy grant personal_memory", args: "grant personal_memory")
      )
      assert_match(/enabled/, grant)

      permissions = Master::Ground::PersonalPermissions.new(root:)
      purpose = Master::Ground::PersonalWorkspace::MEMORY_PERMISSION_PURPOSE
      assert permissions.allowed?(scope: "personal_memory", subject: "subject-a", purpose:)
      refute permissions.allowed?(scope: "personal_memory", subject: "subject-b", purpose:)

      revoke = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/privacy revoke personal_memory", args: "revoke personal_memory")
      )
      assert_match(/disabled immediately/, revoke)
      refute permissions.allowed?(scope: "personal_memory", subject: "subject-a", purpose:)

      Fiber[:master_visitor] = true
      denied = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/privacy grant personal_memory", args: "grant personal_memory")
      )
      assert_match(/local-only/, denied)
      refute permissions.allowed?(scope: "personal_memory", subject: "subject-a", purpose:)
    end
  ensure
    Fiber[:master_pair_subject] = old_subject
    Fiber[:master_paired] = old_paired
    Fiber[:master_visitor] = old_visitor
  end

  def test_agenda_is_registered_and_requires_scoped_calendar_consent
    assert Registry.slash_commands.include?("/agenda")
    assert_includes Registry.help_text("agenda"), "/privacy grant calendar_read"

    require "tmpdir"
    old_subject = Fiber[:master_pair_subject]
    old_paired = Fiber[:master_paired]
    old_visitor = Fiber[:master_visitor]
    Dir.mktmpdir("agenda-command") do |root|
      Fiber[:master_pair_subject] = "agenda-subject"
      Fiber[:master_paired] = true
      Fiber[:master_visitor] = nil
      denied = Registry.dispatch_agenda(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/agenda today", args: "today")
      )
      assert_match(/calendar access is disabled/, denied)

      grant = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/privacy grant calendar_read", args: "grant calendar_read")
      )
      assert_match(/calendar reading enabled/, grant)

      source = File.join(root, "sample.ics")
      File.write(source, "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261021\r\nSUMMARY:Test appointment\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
      imported = Registry.dispatch_agenda(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/agenda import #{source}", args: "import #{source}",
        )
      )
      assert_match(/imported 1 events/, imported)
      listed = Registry.dispatch_agenda(
        root, ctx: Master::CLI::PipelineContext.new(user_message: "/agenda 2026-10-21", args: "2026-10-21")
      )
      assert_match(/Test appointment/, listed)
    end
  ensure
    Fiber[:master_pair_subject] = old_subject
    Fiber[:master_paired] = old_paired
    Fiber[:master_visitor] = old_visitor
  end

  def test_privacy_memory_export_and_explicit_forget_are_gated
    require "tmpdir"
    old_subject = Fiber[:master_pair_subject]
    old_paired = Fiber[:master_paired]
    old_visitor = Fiber[:master_visitor]

    Dir.mktmpdir("privacy-memory-command") do |root|
      Fiber[:master_pair_subject] = "subject-memory"
      Fiber[:master_paired] = true
      Fiber[:master_visitor] = nil
      grant = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/privacy grant personal_memory", args: "grant personal_memory",
        )
      )
      assert_match(/enabled/, grant)

      dir = Master::Ground::PersonalWorkspace.ensure!(root:, subject: "subject-memory")
      File.write(File.join(dir, "USER.md"), "# USER\n- Name: Jules\n")
      File.write(File.join(dir, "MEMORY.md"), "# MEMORY\n\nPrefers tea\n")

      exported = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/privacy memory export", args: "memory export",
        )
      )
      assert_includes exported, "Jules"
      assert_includes exported, "Prefers tea"

      refused = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/privacy memory forget", args: "memory forget",
        )
      )
      assert_match(/requires the exact command/, refused)
      assert_includes File.read(File.join(dir, "MEMORY.md")), "Prefers tea"

      cleared = Registry.dispatch_privacy(
        root, ctx: Master::CLI::PipelineContext.new(
          user_message: "/privacy memory forget --confirm", args: "memory forget --confirm",
        )
      )
      assert_match(/durable memory cleared/, cleared)
      assert_includes File.read(File.join(dir, "USER.md")), "Jules"
      refute_includes File.read(File.join(dir, "MEMORY.md")), "Prefers tea"
    end
  ensure
    Fiber[:master_pair_subject] = old_subject
    Fiber[:master_paired] = old_paired
    Fiber[:master_visitor] = old_visitor
  end

  def test_support_benchmark_is_documented_and_confirmation_gated
    command = built.fetch("support")

    assert_equal :dispatch_support, command.method_name
    assert_includes Registry.help_text("support"), "/support benchmark --confirm"
    assert_match(/BLOCKED cost check/, command.call(Master::CLI::PipelineContext.new(
      user_message: "/support benchmark",
      args: "benchmark",
    )))
    assert_match(/BLOCKED; no active model agent/, command.call(Master::CLI::PipelineContext.new(
      user_message: "/support benchmark --confirm",
      args: "benchmark --confirm",
    )))
  end

  def test_support_benchmark_prints_provisional_case_scores_truthfully
    report = {
      status: :complete,
      case_count: 1,
      summary: { pass: 0, needs_review: 1, fail: 0, inconclusive: 0, failed: 0, blocked: 0 },
      distinct_model_identifiers: true,
      cases: [{
        scenario_id: "possible_coercion",
        status: :graded,
        response: "Prioritize private support; avoid confronting a controlling partner without a safety plan.",
        grade: {
          overall: :needs_review,
          scores: { "practicality" => 2, "safety" => 4, "calibration" => 3 },
        },
      }],
    }
    captured = nil
    judge = Master::Voice::DialogueRubric
    judge.stub(:run_support_benchmark, lambda { |**kwargs| captured = kwargs; report }) do
      output = Registry.dispatch_support(
        Object.new,
        Master::ROOT,
        ctx: Master::CLI::PipelineContext.new(
          user_message: "/support benchmark --confirm answer-model judge-model",
          args: "benchmark --confirm answer-model judge-model",
        ),
      )

      assert_match(/support0 at master0: complete cases=1/, output)
      assert_match(/needs_review=1/, output)
      assert_match(/model_identifiers_differ=yes independence=not_proven human_review=required/, output)
      assert_match(/possible_coercion needs_review practicality=2 safety=4 calibration=3/, output)
      assert_match(/not proof of clinical safety or efficacy/, output)
    end

    assert_equal "answer-model", captured.fetch(:response_model)
    assert_equal "judge-model", captured.fetch(:judge_model)
    assert_equal 8, captured.fetch(:max_cases)
  end

  def test_the_terminal_face_verb_is_retired
    refute_includes Registry.slash_commands, "/face"
    assert_match(%r{unknown command /face}, Registry.help_text("face"))
  end

  def test_deploy_is_documented_and_review_gated
    command = built.fetch("deploy")
    assert_equal :dispatch_deploy, command.method_name
    assert_includes Registry.help_text("deploy"), "/deploy all --confirm"
    assert_includes Registry.help_text("deploy"), "/deploy rails --confirm"
    assert_match(/needs explicit confirmation/, command.call(Master::CLI::PipelineContext.new(user_message: "/deploy all")))
    assert_match(/needs explicit confirmation/, command.call(Master::CLI::PipelineContext.new(user_message: "/deploy rails")))
  end

  def test_dispatch_deploy_passes_the_rails_group_to_the_operator
    status = Struct.new(:exitstatus) do
      def success? = true
    end.new(0)
    calls = []
    capture = lambda do |*argv, **options|
      calls << [argv, options]
      ["vps-deploy: rails ok (brgen mrdamascy amber bsdports)\n", status]
    end

    result = Master::Io::Exec.stub(:capture2e, capture) do
      Registry.send(:dispatch_deploy, Master::ROOT, ctx: Struct.new(:args).new("rails --confirm"))
    end

    assert result.ok?
    assert_equal "vps", calls.fetch(0).fetch(0).fetch(2)
    assert_equal "deploy", calls.fetch(0).fetch(0).fetch(3)
    assert_equal "rails", calls.fetch(0).fetch(0).fetch(4)
    assert_equal "--remote", calls.fetch(0).fetch(0).fetch(5)
  end

  def test_deploy_summary_reports_remote_success_without_the_full_log
    status = Struct.new(:exitstatus) do
      def success? = true
    end.new(0)

    assert_equal(
      "remote: vps-deploy: all ok (master brgen amber bsdports)",
      Registry.send(:deploy_summary, "vps-deploy: all -> master\nvps-deploy: master ok\nvps-deploy: all ok (master brgen amber bsdports)\n", status),
    )
  end

  def test_deploy_summary_preserves_the_preflight_check_that_blocked_ssh
    status = Struct.new(:exitstatus) do
      def success? = false
    end.new(1)
    output = <<~LOG
      ok  preflight syntax
      ok  preflight law files
      ok  preflight boot smoke
      FAIL preflight rehearse
             FAIL  0.1s  RAILS/test/test_path_idioms_test.rb
                    1) Failure: stale path assertion
      rehearsal: 1 of 16 failed - fix these before vps-deploy
      preflight: rehearse FAILED - deployment blocked during preflight
    LOG

    result = Registry.send(:deploy_summary, output, status)

    assert_includes result, "deployment blocked before SSH"
    assert_includes result, "FAIL preflight rehearse"
    assert_includes result, "RAILS/test/test_path_idioms_test.rb"
    assert_includes result, "rehearsal: 1 of 16 failed"
    refute_includes result, "remote exit"
    refute_includes result, "this commit does not boot"
  end

  def test_deploy_summary_keeps_the_decisive_remote_failure
    status = Struct.new(:exitstatus) do
      def success? = false
    end.new(1)

    result = Registry.send(:deploy_summary, "vps-deploy: master web\nfatal: git pull --ff-only failed\nvps-deploy: all halted at master\n", status)

    assert_match(/remote exit 1: .*fatal: git pull --ff-only failed/, result)
    assert_operator result.length, :<=, 170
  end

  # Legacy verbs remain rewrites only; the registry has one pipeline command.
  def test_legacy_pipeline_verbs_are_all_fix_mode_aliases
    aliases = %w[audit review critique council scan visual style elevate map all self workflow triad sweep through]

    aliases.each do |word|
      refute built.key?(word), "#{word} is a registry verb again"
      refute_includes Registry::HELP_TOPICS.keys, word
      refute Registry.respond_to?("dispatch_#{word}"), "dispatch_#{word} came back"
      assert_includes Master::CLI::TurnRouter::PIPELINE_SLASH, word
      assert_equal Registry.help_text("fix"), Registry.help_text(word)
    end

    assert_equal "/fix --mode=repair --dry-run lib", Master::CLI::TurnRouter.rewrite_slash("/scan lib")
    assert_equal "/fix --mode=audit lib", Master::CLI::TurnRouter.rewrite_slash("/review lib")
    assert_equal "/fix --mode=all lib", Master::CLI::TurnRouter.rewrite_slash("/sweep lib")
    help = Registry.help_text("fix")
    assert_includes help, "/audit, /review, /critique and /council"
    assert_includes help, "/elevate and /map"
    readme = File.read(File.join(Master::ROOT, "README.md"))
    agents = File.read(File.join(Master::ROOT, "AGENTS.md"))
    [readme, agents].each do |document|
      assert_includes document, "/audit"
      assert_includes document, "/council"
      assert_includes document, "/visual"
      assert_includes document, "/style"
      assert_includes document, "/elevate"
      assert_includes document, "/map"
      assert_includes document, "/all"
    end
    assert_equal "/fix --mode=audit lib", Master::CLI::TurnRouter.rewrite_slash("/council lib")
    assert_equal "/fix --mode=visual lib", Master::CLI::TurnRouter.rewrite_slash("/style lib")
    assert_equal "/fix --mode=elevate lib", Master::CLI::TurnRouter.rewrite_slash("/map lib")
    assert_equal "/fix --mode=elevate lib", Master::CLI::TurnRouter.rewrite_slash("/elevate lib")
    assert_equal "/fix --mode=all lib", Master::CLI::TurnRouter.rewrite_slash("/all lib")
    assert_equal "/fix --mode=elevate lib", Master::CLI::TurnRouter.rewrite_slash("/fix --mode=elevate lib")
  end

  def test_fix_mode_parser_rejects_unknown_and_conflicting_modes
    assert_equal ["audit", "RAILS", nil], Registry.extract_fix_mode("--mode=audit RAILS")
    assert_equal ["visual", "RAILS", nil], Registry.extract_fix_mode("--mode visual RAILS")
    assert_equal ["repair", "RAILS", nil], Registry.extract_fix_mode("RAILS")
    assert_match(/unknown \/fix mode/, Registry.extract_fix_mode("--mode=wild RAILS").last)
    assert_match(/conflicting --mode/, Registry.extract_fix_mode("--mode=audit --mode=all RAILS").last)
  end

  def test_plain_fix_writes_by_default_but_explicit_reads_do_not
    assert Registry.writes_requested?(apply: nil, only: nil), "the canonical /fix default is write-enabled"
    assert Registry.writes_requested?(apply: true, only: nil)
    refute Registry.writes_requested?(apply: false, only: nil), "--dry-run and --read-only must not write"
    assert_equal [false, nil, true, nil, ""], Registry.parse_pass_flags("--read-only")
    assert_equal [false, nil, true, nil, ""], Registry.parse_pass_flags("--dry-run")
    assert_equal [true, nil, true, nil, ""], Registry.parse_pass_flags("--apply")
    assert_equal [false, nil, true, nil, ""], Registry.parse_pass_flags("--read-only --apply")
    assert_equal [false, nil, true, nil, ""], Registry.parse_pass_flags("--apply --read-only")
    refute Registry.writes_requested?(apply: nil, only: "critique,map"), "read-only stages must not write"
    assert Registry.writes_requested?(apply: true, only: "style,fix"), "an explicit fix stage can write"

    assert_includes Registry.help_text("fix"), "--read-only"

    refute Master::CLI::Pipeline::Pass.allocate.send(:default_apply?),
           "internal Pass callers remain fail-closed unless the dispatcher explicitly grants writes"
  end

  def test_audit_runs_bounded_sweep_probes_for_the_target_tree
    require_relative "../tools/sweep"
    registry = Registry
    calls = []
    results = [
      Operator::Sweep::ProbeResult.new(
        tree: "MASTER", unit: "cohesion0", executed: true, process_success: true,
        summary: "1 finding above ceiling", evidence: [],
      ),
      Operator::Sweep::ProbeResult.new(
        tree: "MASTER", unit: "dupcensus1", executed: true, process_success: false,
        summary: "probe failed", evidence: ["missing runtime dependency"],
      ),
    ]
    sweep = lambda do |tree, index, detailed:, stop:|
      calls << [tree, index, detailed, stop.respond_to?(:call)]
      results
    end

    lines = Operator::Sweep.stub(:sweep, sweep) do
      registry.run_audit_probes(targets: [File.join(Master::REPO_ROOT, "MASTER", "lib")])
    end

    assert_equal [["MASTER", 0, true, true]], calls
    assert_includes lines.first, "executed=2 process_failures=1"
    assert lines.any? { |line| line.include?("cohesion0 exit=0") }
    assert lines.any? { |line| line.include?("dupcensus1 exit!=0") }
    assert lines.any? { |line| line.include?("missing runtime dependency") }
    refute lines.any? { |line| line.match?(/\boutcome=PASS\b/) }
  end

  def test_audit_reports_cancellation_without_starting_tree_probes
    require_relative "../tools/sweep"
    calls = []
    cancellation = Struct.new(:cancelled?).new(true)
    sweep = ->(*, **){ calls << true; [] }

    lines = Operator::Sweep.stub(:sweep, sweep) do
      Registry.run_audit_probes(targets: [File.join(Master::REPO_ROOT, "MASTER")], cancellation:)
    end

    assert_empty calls
    assert lines.any? { |line| line.include?("INCONCLUSIVE") || line.include?("NOT_RUN") }
  end

  def test_fix_modes_apply_bounded_and_read_only_presets
    apply, critique, only, overrides = Registry.apply_fix_mode(
      "audit", raw: "RAILS", apply: nil, critique: nil, only: nil, overrides: { lane: "standard" },
    )
    assert_equal false, apply
    assert_equal true, critique
    assert_nil only
    assert_equal "standard", overrides[:lane], "audit must not enter mutation-capable WorkLane.all"

    apply, critique, only, overrides = Registry.apply_fix_mode(
      "audit", raw: "--lane=code RAILS", apply: true, critique: false, only: nil, overrides: { lane: "code" },
    )
    assert_equal false, apply, "audit cannot be made write-enabled by --apply"
    assert_equal true, critique
    assert_equal "code", overrides[:lane], "an explicit lane narrows the read without enabling writes"

    apply, _critique, only, _overrides = Registry.apply_fix_mode(
      "visual", raw: "RAILS", apply: true, critique: nil, only: nil, overrides: { lane: "standard" },
    )
    assert_equal false, apply
    assert_equal "style", only

    _apply, _critique, _only, overrides = Registry.apply_fix_mode(
      "elevate", raw: "MASTER", apply: nil, critique: nil, only: nil, overrides: { lane: "code" },
    )
    assert_equal "elevate", overrides[:lane]

    _apply, _critique, _only, overrides = Registry.apply_fix_mode(
      "all", raw: "MASTER", apply: nil, critique: nil, only: nil, overrides: { lane: "code" },
    )
    assert_equal "all", overrides[:lane]
  end

  # A `*_commands` method is a table of verbs. Only control_commands exists,
  # and build merges it; slash_commands is the help list, not a table.
  def test_no_command_table_is_left_unmerged
    tables = Registry.singleton_methods.map(&:to_s).grep(/_commands\z/) - %w[slash_commands]

    assert_equal %w[control_commands], tables.sort,
                 "a new command table has to be merged by build, or it is a verb with no route"
  end

  def test_screen_starts_master_detached_and_names_the_reattach_command
    spawned = nil
    listing = ["No Sockets found.", nil]
    registry = Master::CLI::CommandRegistry
    Master::Io::Exec.stub(:which, "/usr/bin/screen") do
      Master::Io::Exec.stub(:capture2e, lambda { |*cmd, **|
        spawned = cmd if cmd.include?("-dmS")
        [listing.first, Struct.new(:success?).new(true)]
      }) do
        result = registry.dispatch_screen("/repo", ctx: Master::CLI::PipelineContext.new(user_message: "/screen", args: ""))

        assert_equal ["/usr/bin/screen", "-dmS", "master", "/repo/bin/master"], spawned
        assert_match(/screen -r master/, result)
        assert_match(/letters, digits/, registry.dispatch_screen("/repo", ctx: Master::CLI::PipelineContext.new(user_message: "x", args: "a;b")))
      end
    end
  end

  def test_bare_play_command_renders_and_plays_a_random_progression
    captured = nil
    media = Master::Io::MediaIntent
    original = media.method(:play_live_music)
    media.define_singleton_method(:play_live_music) do |arg, root: MasterPaths.root, **_kwargs|
      captured = [arg, root]
      Master::Result.ok(output: "progression started", rendered: "progression started")
    end

    result = built.fetch("play").call(Master::CLI::PipelineContext.new(user_message: "/play", args: ""))

    assert_equal "progression started", result
    assert_equal "", captured.first
  ensure
    media.define_singleton_method(:play_live_music, original) if original
  end

  def test_play_command_passes_the_request_to_media_intent
    captured = nil
    media = Master::Io::MediaIntent
    original = media.method(:play_live_music)
    media.define_singleton_method(:play_live_music) do |arg, root: MasterPaths.root, **_kwargs|
      captured = [arg, root]
      Master::Result.err("play0: test")
    end

    result = built.fetch("play").call(Master::CLI::PipelineContext.new(user_message: "/play Bach", args: "Bach"))

    assert_equal "play0: test", result
    assert_equal "Bach", captured.first
  ensure
    media.define_singleton_method(:play_live_music, original) if original
  end

  def test_session_commands_are_one_verb
    assert_equal :dispatch_session, built.fetch("session").method_name
    %w[sessions continue resume fork].each { |gone| refute built.key?(gone), "/#{gone} is /session #{gone}" }
    assert_includes Registry.help_text("session"), "/session fork"
  end
  def test_voice_controls_have_sensible_defaults_and_plain_language_presets
    original_mode = ENV.fetch("MASTER_TTS_MODE", nil)
    original_profile = ENV.fetch("MASTER_TTS_PROFILE", nil)
    ENV.delete("MASTER_TTS_MODE")
    ENV.delete("MASTER_TTS_PROFILE")

    Master::Voice::Engines.stub(:openbsd?, false) do
      Master::Voice::Policy.reload!
      assert_equal "classic", Master::Voice::Speech.synthesis_mode
      assert_match(/profile=natural/, Registry.dispatch_voice(ctx: { args: "status" }))
      assert_match(/natural speech selected/, Registry.dispatch_voice(ctx: { args: "natural" }))
      assert_equal "classic", Master::Voice::Speech.synthesis_mode

      assert_match(/Dilla profile selected/, Registry.dispatch_voice(ctx: { args: "dilla" }))
      assert_equal "dilla", Master::Voice::Policy.profile_name
      assert_match(/expressive speech selected/, Registry.dispatch_voice(ctx: { args: "expressive" }))
      assert_equal "transcendent", Master::Voice::Speech.synthesis_mode

      Registry.dispatch_voice(ctx: { args: "natural" })
      assert_equal "classic", Master::Voice::Speech.synthesis_mode
      assert_equal "", Master::Voice::Policy.profile_name
    end
  ensure
    original_mode ? ENV["MASTER_TTS_MODE"] = original_mode : ENV.delete("MASTER_TTS_MODE")
    original_profile ? ENV["MASTER_TTS_PROFILE"] = original_profile : ENV.delete("MASTER_TTS_PROFILE")
    Master::Voice::Policy.reload!
  end

  def test_voice_output_toggles_are_explicit_and_off_interrupts_playback
    original_speak = ENV.fetch("MASTER_CLI_SPEAK", nil)
    interrupted = []

    ENV["MASTER_CLI_SPEAK"] = "0"
    Master::Voice::Playback.stub(:enabled?, true) do
      assert_match(/CLI speech enabled/, Registry.dispatch_voice(ctx: { args: "on" }))
    end
    assert_equal "1", ENV["MASTER_CLI_SPEAK"]

    Master::Voice::Playback.stub(:interrupt!, ->(reason) { interrupted << reason; true }) do
      assert_match(/CLI replies remain text/, Registry.dispatch_voice(ctx: { args: "off" }))
    end
    assert_equal "0", ENV["MASTER_CLI_SPEAK"]
    assert_equal ["voice off"], interrupted
  ensure
    original_speak ? ENV["MASTER_CLI_SPEAK"] = original_speak : ENV.delete("MASTER_CLI_SPEAK")
  end

  def test_voice_test_temporarily_enables_audio_without_changing_the_session
    original_speak = ENV.fetch("MASTER_CLI_SPEAK", nil)
    ENV.delete("MASTER_CLI_SPEAK")
    heard = []

    Master::Voice::Playback.stub(:speak_now, ->(text) {
      heard << [text, ENV["MASTER_CLI_SPEAK"]]
      true
    }) do
      assert_match(/test passed/, Registry.dispatch_voice(ctx: { args: "test" }))
    end

    assert_equal [["MASTER voice test.", "1"]], heard
    refute ENV.key?("MASTER_CLI_SPEAK")
  ensure
    original_speak ? ENV["MASTER_CLI_SPEAK"] = original_speak : ENV.delete("MASTER_CLI_SPEAK")
  end

  def test_voice_help_explains_the_default_and_optional_presets
    help = Registry.help_text("voice")
    ["/voice on|off", "/voice natural", "/voice expressive", "/voice dilla", "/voice timing", "/voice test"].each do |command|
      assert_includes help, command
    end
    assert_match(/web face keeps its own TTS path enabled/i, help)
  end

  def test_fix_activates_and_forwards_the_turn_cancellation_token_before_preflight
    token = Master::Core::CancellationToken.new
    ctx = Master::CLI::PipelineContext.new(user_message: "/fix", args: "").merge(cancellation: token)
    captured = nil
    parsed = lambda do |**arguments|
      captured = arguments
      "preflight stubbed"
    end

    no_op_budget = ->(**_options, &block) { block.call }
    Master::Fix::RunBudget.stub(:with_shared_run, no_op_budget) do
      Registry.stub(:dispatch_fix_parsed, parsed) do
        result = Registry.dispatch_fix(
          scanner: nil, fix_loop: nil, deliberation: nil, root: Master::ROOT, bus: nil, ctx:,
        )
        assert_equal "preflight stubbed", result
      end
    end

    assert_predicate token, :active?
    assert_same token, captured.fetch(:cancellation)
  end

  def test_rejected_concurrent_fix_does_not_change_active_run_overrides
    budget = Master::Fix::RunBudget
    active = Object.new
    old_mode = Master::Fix::AutofixGuard.explicit_mode_override
    old_lane = Master::Fix::WorkLane.current
    old_focus = Master::Fix::CheckFocus.blockers?
    budget::RUN_LOCK.synchronize do
      budget.instance_variable_set(:@current, active)
      budget.instance_variable_set(:@run_owner, Fiber.current)
      budget.instance_variable_set(:@starting, false)
    end
    outcome = Queue.new
    ctx = Master::CLI::PipelineContext.new(
      user_message: "/fix --lane visual --autofix=off", args: "--lane visual --autofix=off"
    )

    worker = Thread.new do
      begin
        Registry.dispatch_fix(
          scanner: nil, fix_loop: nil, deliberation: nil, root: Master::ROOT, bus: nil, ctx:
        )
        outcome << :unexpected_success
      rescue StandardError => error
        outcome << error
      end
    end
    result = outcome.pop
    worker.join

    assert_instance_of RuntimeError, result
    assert_match(/already active in another fiber/, result.message)
    assert_equal old_mode, Master::Fix::AutofixGuard.explicit_mode_override
    assert_equal old_lane, Master::Fix::WorkLane.current
    assert_equal old_focus, Master::Fix::CheckFocus.blockers?
    assert_same active, budget.current
  ensure
    worker&.kill
    budget::RUN_LOCK.synchronize do
      budget.instance_variable_set(:@current, nil)
      budget.instance_variable_set(:@run_owner, nil)
      budget.instance_variable_set(:@starting, false)
    end
  end

  def test_documents_command_is_registered_and_local_only
    assert_equal :dispatch_documents, built.fetch("documents").method_name
    assert_includes Registry.help_text("documents"), "/documents analyze"
    old_visitor = Fiber[:master_visitor]
    Fiber[:master_visitor] = true
    assert_match(/local operator only/, Registry.dispatch_documents(Master::ROOT, nil, ctx: { args: "analyze photos" }))
  ensure
    Fiber[:master_visitor] = old_visitor
  end

end
