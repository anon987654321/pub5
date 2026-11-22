# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require "json"
require_relative "../tools/owner_registry_tasks"
require_relative "../lib/fix/adaptive_journey"

# The task executor reads explicit, proof-bearing contracts from the registries
# that own the work. Prose, inferred paths and guessed commands never enter it.
class TestOwnerRegistryTasks < Minitest::Test
  def entries = @entries ||= Backlog.generate

  EXPECTED_TASK_IDS = %w[
    inconclusive_aging constitution_self_budget brgen_feed_ranking_deterministic
    amber_similarity_right_sized master_fleet_panel free_compute_design_of_record
  ].sort.freeze

  def test_only_explicit_owner_registry_tasks_enter_unattended_intake
    assert_equal EXPECTED_TASK_IDS, entries.map { |row| row.fetch(:id) }.sort
    assert entries.all? { |row| row[:registry_source] && row[:registry_digest] }
    refute entries.any? { |row| row[:tree] == "operator" }
  end

  def test_every_task_has_one_tree_exact_existing_scope_and_allowlisted_acceptance
    entries.each do |row|
      assert_includes Backlog::TREES, row.fetch(:tree)
      assert_includes Backlog::KINDS, row.fetch(:kind)
      assert_includes Backlog::SIZES, row.fetch(:size)
      refute_empty row.fetch(:scope_paths)
      row.fetch(:scope_paths).each do |relative|
        assert relative.start_with?("#{row.fetch(:tree)}/"), "#{row[:id]} crosses tree boundary: #{relative}"
        absolute = File.expand_path(relative, Master::REPO_ROOT)
        assert absolute.start_with?(Master::REPO_ROOT + File::SEPARATOR)
        assert File.file?(absolute), "#{row[:id]} scope is not an existing file: #{relative}"
        refute File.symlink?(absolute), "#{row[:id]} scope is a symlink: #{relative}"
      end
      proof = Backlog::ProofMap.execution_spec(
        row.fetch(:done_when), tree: row.fetch(:tree), repo_root: Master::REPO_ROOT
      )
      refute_nil proof, "#{row[:id]} has no bounded acceptance mapping"
    end
  end

  def test_registry_digests_and_task_identity_change_with_the_owner_record
    row = entries.first
    changed = row.merge(text: "#{row.fetch(:text)} changed")
    refute_equal Backlog.item_digest(row), Backlog.item_digest(changed)
    assert_match(/\A[0-9a-f]{64}\z/, Backlog.registry_digest(row))
  end
  def test_operator_seams_and_acceptance_only_ledgers_are_not_auto_queued
    operator = YAML.safe_load_file(File.join(Master::REPO_ROOT, "MASTER/data/operator_seams.yml"))
    ux = YAML.safe_load_file(File.join(Master::REPO_ROOT, "MASTER/data/law/ux_refinements.yml"))
    rails = YAML.safe_load_file(File.join(Master::REPO_ROOT, "RAILS/refinements.yml"))
    refute operator.fetch("seams").any? { |row| row.key?("agent_task") }
    refute ux.fetch("refinements").any? { |row| row.key?("agent_task") }
    refute rails.fetch("items").any? { |row| row.key?("agent_task") }
    refute entries.any? { |row| row[:registry_source].end_with?("operator_seams.yml") }
  end

  def test_task_reader_does_not_create_a_second_generated_backlog
    refute defined?(Backlog::Store)
    refute defined?(Backlog::Reader)
    refute defined?(Backlog::Classify)
    refute File.exist?(File.join(Master::REPO_ROOT, "MASTER/data/backlog.yml"))
  end

  def test_proof_map_covers_explicit_test_lint_and_runtime_commands
    map = Backlog::ProofMap

    assert_equal ["full_suite"], map.types_for(done_when: "rake test")
    assert_equal ["full_suite"], map.types_for(done_when: "cd MASTER && MASTER_TEST_JOBS=1 bundle exec rake test")
    assert_equal ["full_suite"], map.types_for(done_when: "ruby RAILS/test/run_all.rb")
    assert_equal ["full_suite"], map.types_for(done_when: "cd RAILS && ruby test/run_all.rb")
    assert_equal ["full_suite"], map.types_for(done_when: "cd RAILS/brgen && bin/ci")
    assert_equal ["focused_tests"], map.types_for(done_when: "rake test:fix:convergence")
    assert_equal ["focused_tests"], map.types_for(done_when: "ruby -Itest test/test_fix_kernel.rb")
    assert_equal ["focused_tests"], map.types_for(done_when: "ruby MASTER/test/test_fix_kernel.rb")
    assert_equal ["focused_tests"], map.types_for(done_when: "MASTER/bin/operator test MASTER/test/test_fix_kernel.rb")
    assert_equal ["focused_tests"], map.types_for(done_when: "cd MASTER && bin/operator test test/test_fix_kernel.rb")
    assert_equal ["focused_tests"], map.types_for(done_when: "rspec spec/fix_spec.rb")
    assert_equal ["law_assessment"], map.types_for(done_when: "rake lint:law_parity")
    assert_equal ["law_assessment"], map.types_for(done_when: "rake audit")
    assert_equal ["law_assessment"], map.types_for(done_when: "ruby MASTER/checks/runner.rb --all")
    assert_equal ["law_assessment"], map.types_for(done_when: "cd MASTER && bundle exec ruby checks/runner.rb --scan-only architecture layout_suite")
    assert_equal ["law_assessment"], map.types_for(done_when: "MASTER/bin/operator check --scan-only --tree=MASTER")
    assert_equal ["rendered_evidence"], map.types_for(done_when: "MASTER/bin/operator visual sweep RAILS/brgen --one-page")
    assert_equal ["accessibility_review"], map.types_for(done_when: "bin/operator accessibility")
    assert_equal ["runtime_evidence"], map.types_for(done_when: "pfctl -nf /etc/pf.conf")
  end

  def test_acceptance_command_specs_are_argv_only_and_read_only
    repository = File.expand_path("..", Backlog::MASTER_ROOT)
    map = Backlog::ProofMap

    focused = map.execution_spec(
      "cd MASTER && MASTER_TEST_JOBS=1 bundle exec ruby -Itest test/test_fix_kernel.rb",
      tree: "MASTER", repo_root: repository
    )
    assert_equal "focused_tests", focused.fetch(:proof_type)
    assert_equal "MASTER", focused.fetch(:cwd_relative)
    assert_equal "1", focused.fetch(:env).fetch("MASTER_TEST_JOBS")
    assert_equal :ruby_bundle, focused.fetch(:launcher)
    assert_includes focused.fetch(:argv), File.join(Backlog::MASTER_ROOT, "test/test_fix_kernel.rb")

    full = map.execution_spec("rake test", tree: "MASTER", repo_root: repository)
    assert_equal "full_suite", full.fetch(:proof_type)
    assert_equal :bundle, full.fetch(:launcher)
    assert_equal ["rake", "test"], full.fetch(:argv)

    check = map.execution_spec(
      "MASTER/bin/operator check --scan-only --tree=MASTER",
      tree: "MASTER", repo_root: repository
    )
    assert_equal "law_assessment", check.fetch(:proof_type)
    assert_equal :ruby_bundle, check.fetch(:launcher)

    refute map.execution_spec(
      "MASTER/bin/operator check --tree=MASTER", tree: "MASTER", repo_root: repository
    ), "operator check without a read-only flag must not be auto-run"
    refute map.execution_spec(
      "rake test; echo unsafe", tree: "MASTER", repo_root: repository
    ), "shell operators must not enter argv execution"
    refute map.execution_spec(
      "ssh host.example 'deploy now'", tree: "OPENBSD", repo_root: repository
    ), "remote commands must remain outside unattended intake"
    refute map.execution_spec(
      "RUBYOPT=-r/tmp/hook.rb rake test", tree: "MASTER", repo_root: repository
    ), "unknown environment injection must be refused"
    refute map.execution_spec(
      "ruby -e 'puts 1'", tree: "MASTER", repo_root: repository
    ), "arbitrary Ruby evaluation must not enter unattended intake"
  end

  def test_execution_spec_preserves_the_original_command_with_allowed_environment_prefixes
    command = "cd MASTER && MASTER_TEST_JOBS=1 bundle exec rake test"
    spec = Backlog::ProofMap.execution_spec(command, tree: "MASTER", repo_root: Master::REPO_ROOT)

    refute_nil spec
    assert_equal "full_suite", spec.fetch(:proof_type)
    assert_equal :bundle, spec.fetch(:launcher)
    assert_equal ["rake", "test"], spec.fetch(:argv)
    assert_equal "1", spec.fetch(:env).fetch("MASTER_TEST_JOBS")
    assert_equal "MASTER", spec.fetch(:cwd_relative)
    assert_equal Digest::SHA256.hexdigest(command), spec.fetch(:command_digest)
    assert_equal 1800, spec.fetch(:timeout)
  end

  def test_proof_map_does_not_guess_unknown_commands_or_empty_acceptance
    map = Backlog::ProofMap

    assert_empty map.types_for(done_when: nil)
    assert_empty map.types_for(done_when: "git status --short")
    assert_empty map.types_for(done_when: "ruby tools/unknown-check.rb")
    refute map.valid_types?([])
    refute map.valid_types?(["made_up_proof"])
    assert map.valid_types?(["focused_tests", "runtime_evidence"])
  end

  def test_executor_queues_only_a_single_tree_mechanical_item
    row = {
      id: "safe-task", text: "Repair the existing MASTER source and verify it.",
      tree: "MASTER", kind: "mechanical", scope_paths: ["MASTER/lib/example.rb"],
      done_when: "rake test", size: "s", section: "MASTER",
    }
    fake_mission = Class.new do
      class << self
        attr_accessor :queued
        def current(root:) = nil
      end
      def initialize(root:); end
      def ensure_queued!(**attributes)
        self.class.queued = attributes
      end
    end

    Dir.mktmpdir("backlog-executor") do |root|
      Dir.mktmpdir("backlog-repo") do |repo_root|
        full = File.join(repo_root, "MASTER/lib/example.rb")
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, "VALUE = 1\n")
        executor = Backlog::Executor.new(root:, repo_root:, mission_class: fake_mission)
        Backlog.stub(:generate, [row]) do
          assert_equal :queued, executor.enqueue_next!
        end

        queued = fake_mission.queued
        assert_equal "backlog", queued.fetch(:origin)
        assert_equal true, queued.fetch(:auto_continue)
        assert_equal root, queued.fetch(:scope)
        plan = JSON.parse(queued.fetch(:plan))
        assert_equal "safe-task", plan.fetch("item_id")
        assert_equal ["MASTER/lib/example.rb"], plan.fetch("scope_paths")
      end
    end
  end

  def test_adaptive_journey_selects_a_prerequisite_before_its_dependent_route
    planner = Master::Fix::AdaptiveJourney.new
    evidence = [
      { id: "source", sha256: "a" * 64, verified: true },
      { id: "command", sha256: "b" * 64, verified: true },
    ]
    routes = [
      { id: "release-preflight", actions: ["verify deployment preflight"], evidence_ids: %w[source],
        impact: 0.7, confidence: 0.9, priority: 0.7, cost: 0.8, risk: 0.1, reversibility: "easy" },
      { id: "app-release", actions: ["validate active application release"], evidence_ids: %w[source command],
        impact: 1.0, confidence: 0.95, priority: 1.0, cost: 0.2, risk: 0.05,
        reversibility: "easy", dependencies: ["release-preflight"] },
    ]

    first = planner.choose(routes:, verified_evidence: evidence, objective: "")
    assert_equal "release-preflight", first.route.id

    second = planner.choose(
      routes: [routes.last], verified_evidence: evidence, objective: "",
      satisfied_dependencies: ["release-preflight"]
    )
    assert_equal "app-release", second.route.id
  end

  def test_adaptive_journey_does_not_explore_outside_the_winning_priority_band
    planner = Master::Fix::AdaptiveJourney.new
    evidence = [
      { id: "source", sha256: "a" * 64, verified: true },
      { id: "command", sha256: "b" * 64, verified: true },
      { id: "scope", sha256: "c" * 64, verified: true },
    ]
    routes = [
      { id: "release-safety", actions: ["verify vm23 deployment"], evidence_ids: %w[source command scope],
        impact: 0.8, confidence: 0.9, priority: 1.0, cost: 1.0, risk: 0, reversibility: "easy" },
      { id: "studio-suite", actions: ["run studio suite"], evidence_ids: %w[source command scope],
        impact: 0.8, confidence: 0.9, priority: 0.4, cost: 0.1, risk: 0, reversibility: "easy" },
    ]

    decision = planner.choose(routes:, verified_evidence: evidence, objective: "", exploration: true)

    assert_equal "release-safety", decision.route.id
    refute decision.exploration
  end

  def test_adaptive_journey_includes_lower_priority_routes_only_as_explicit_prerequisites
    planner = Master::Fix::AdaptiveJourney.new
    evidence = [
      { id: "source", sha256: "a" * 64, verified: true },
      { id: "command", sha256: "b" * 64, verified: true },
    ]
    routes = [
      { id: "required-preflight", actions: ["verify deployment preflight"], evidence_ids: %w[source],
        impact: 0.7, confidence: 0.9, priority: 0.65, cost: 0.8, risk: 0.1, reversibility: "easy" },
      { id: "release", actions: ["deploy production release"], evidence_ids: %w[source command],
        impact: 1.0, confidence: 0.95, priority: 1.0, cost: 0.2, risk: 0.05,
        reversibility: "easy", dependencies: ["required-preflight"] },
      { id: "cheap-distraction", actions: ["polish studio artwork"], evidence_ids: %w[source command],
        impact: 0.8, confidence: 0.9, priority: 0.1, cost: 0.01, risk: 0.0, reversibility: "easy" },
    ]

    decision = planner.choose(routes:, verified_evidence: evidence, objective: "")

    assert_equal "required-preflight", decision.route.id
    refute decision.exploration
  end

  def test_adaptive_journey_blocks_when_the_highest_priority_route_has_no_ready_dependency
    planner = Master::Fix::AdaptiveJourney.new
    evidence = [
      { id: "source", sha256: "a" * 64, verified: true },
      { id: "command", sha256: "b" * 64, verified: true },
    ]
    routes = [
      { id: "release", actions: ["deploy production release"], evidence_ids: %w[source command],
        impact: 1.0, confidence: 0.95, priority: 1.0, cost: 0.2, risk: 0.05,
        reversibility: "easy", dependencies: ["missing-preflight"] },
      { id: "cheap-distraction", actions: ["polish studio artwork"], evidence_ids: %w[source command],
        impact: 0.8, confidence: 0.9, priority: 0.1, cost: 0.01, risk: 0.0, reversibility: "easy" },
    ]

    error = assert_raises(ArgumentError) do
      planner.choose(routes:, verified_evidence: evidence, objective: "")
    end
    assert_match(/highest-priority routes are blocked/, error.message)
  end

  def test_adaptive_journey_refuses_unverified_or_ungrounded_routes
    planner = Master::Fix::AdaptiveJourney.new
    error = assert_raises(ArgumentError) do
      planner.choose(
        routes: [{ id: "guess", actions: ["rewrite everything"], evidence_ids: ["unverified"],
          impact: 1, confidence: 1, priority: 1, cost: 1, risk: 0, reversibility: "easy" }],
        verified_evidence: [{ id: "unverified", sha256: "not-a-digest", verified: true }],
        objective: ""
      )
    end
    assert_match(/no route has grounded evidence/, error.message)
  end

  def test_adaptive_journey_causal_graph_uses_only_explicit_edges
    graph = Master::Fix::AdaptiveJourney.new.causal_graph([
      { id: "source", kind: "failure", status: "FAIL" },
      { id: "repair", kind: "change", status: "PASS", caused_by: ["source", "missing", "repair"] },
    ])

    assert_equal [["source", "repair"]], graph.fetch("edges")
    assert_equal ["source"], graph.fetch("roots")
  end

  def test_backlog_executor_selects_deployment_safety_before_creative_acceptance
    rows = [
      { id: "studio-check", text: "Run the STUDIO full suite.", tree: "STUDIO", kind: "mechanical",
        scope_paths: ["STUDIO/replicate/test/suite_test.rb"], done_when: "rake test", size: "s", section: "STUDIO acceptance" },
      { id: "openbsd-runner", text: "Run the updated OPENBSD deployment runner and receipt tests.",
        tree: "OPENBSD", kind: "mechanical", scope_paths: ["OPENBSD/test/runner_test.rb"],
        done_when: "rake test", size: "s", section: "OPENBSD production safety" },
    ]
    fake_mission = Class.new do
      class << self
        attr_accessor :queued
        def current(root:) = nil
      end
      def initialize(root:); end
      def ensure_queued!(**attributes)
        self.class.queued = attributes
      end
    end

    Dir.mktmpdir("adaptive-backlog") do |root|
      Dir.mktmpdir("adaptive-repo") do |repo_root|
        rows.each do |row|
          path = File.join(repo_root, row.fetch(:scope_paths).first)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, "class SuiteTest; end\\n")
        end
        executor = Backlog::Executor.new(root:, repo_root:, mission_class: fake_mission)
        Backlog.stub(:generate, rows) do
          assert_equal :queued, executor.enqueue_next!
        end

        plan = JSON.parse(fake_mission.queued.fetch(:plan))
        assert_equal "openbsd-runner", plan.fetch("item_id")
        assert_equal "release_safety", plan.dig("journey", "phase")
        assert_equal 1.0, plan.dig("journey", "priority")
        assert_equal plan.fetch("item_digest"), plan.dig("journey", "route_id")
      end
    end
  end

  def test_executor_refuses_a_missing_target_until_it_is_created
    Dir.mktmpdir("backlog-executor") do |root|
      Dir.mktmpdir("backlog-repo") do |repo_root|
        row = { id: "missing", text: "Add a new file", tree: "MASTER", kind: "mechanical",
                scope_paths: ["MASTER/lib/not-yet-created.rb"] }
        fake_mission = Class.new do
          def self.current(root:) = nil
          def initialize(root:); end
          def ensure_queued!(**) = flunk("a missing target cannot enter /fix")
        end
        executor = Backlog::Executor.new(root:, repo_root:, mission_class: fake_mission)
        Backlog.stub(:generate, [row]) { assert_equal :idle, executor.enqueue_next! }
      end
    end
  end

  def test_executor_refuses_a_symlinked_parent_even_when_it_resolves_inside_the_repo
    fake_mission = Class.new do
      def self.current(root:) = nil
      def initialize(root:); end
      def ensure_queued!(**) = flunk("a symlinked scope must not be queued")
    end

    Dir.mktmpdir("backlog-symlink-scope") do |root|
      repo_root = File.join(root, "repo")
      real = File.join(repo_root, "MASTER", "real")
      FileUtils.mkdir_p(real)
      File.write(File.join(real, "example.rb"), "VALUE = 1\\n")
      File.symlink(real, File.join(repo_root, "MASTER", "alias"))
      row = {
        id: "symlink-parent", text: "Repair the aliased file and run its tests.",
        tree: "MASTER", kind: "mechanical", scope_paths: ["MASTER/alias/example.rb"],
        done_when: "rake test", size: "s", section: "MASTER",
      }
      executor = Backlog::Executor.new(root: File.join(root, "state"), repo_root:, mission_class: fake_mission)

      Backlog.stub(:generate, [row]) { assert_equal :idle, executor.enqueue_next! }
    end
  end

  def test_executor_refuses_hard_linked_scope_files
    fake_mission = Class.new do
      def self.current(root:) = nil
      def initialize(root:); end
      def ensure_queued!(**) = flunk("a hard-linked scope must not be queued")
    end

    Dir.mktmpdir("backlog-hardlink-scope") do |root|
      repo_root = File.join(root, "repo")
      target = File.join(repo_root, "MASTER", "linked.rb")
      FileUtils.mkdir_p(File.dirname(target))
      outside = File.join(root, "outside.rb")
      File.write(outside, "VALUE = 1\\n")
      File.link(outside, target)
      row = {
        id: "hard-linked", text: "Repair the linked file and run its tests.",
        tree: "MASTER", kind: "mechanical", scope_paths: ["MASTER/linked.rb"],
        done_when: "rake test", size: "s", section: "MASTER",
      }
      executor = Backlog::Executor.new(root: File.join(root, "state"), repo_root:, mission_class: fake_mission)

      Backlog.stub(:generate, [row]) { assert_equal :idle, executor.enqueue_next! }
    end
  end

  def test_executor_refuses_noncanonical_scope_path_aliases
    fake_mission = Class.new do
      def self.current(root:) = nil
      def initialize(root:); end
      def ensure_queued!(**) = flunk("a noncanonical scope alias must not be queued")
    end

    Dir.mktmpdir("backlog-noncanonical-scope") do |root|
      repo_root = File.join(root, "repo")
      target = File.join(repo_root, "MASTER", "safe.rb")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "VALUE = 1\\n")
      row = {
        id: "noncanonical", text: "Repair the source and run its tests.",
        tree: "MASTER", kind: "mechanical",
        scope_paths: ["MASTER/../MASTER/safe.rb"],
        done_when: "rake test", size: "s", section: "MASTER",
      }
      executor = Backlog::Executor.new(root: File.join(root, "state"), repo_root:, mission_class: fake_mission)

      Backlog.stub(:generate, [row]) { assert_equal :idle, executor.enqueue_next! }
    end
  end

  def test_executor_refuses_design_cross_tree_and_operator_rows
    fake_mission = Class.new do
      def self.current(root:) = nil
      def initialize(root:); end
      def ensure_queued!(**) = flunk("ineligible backlog item was queued")
    end
    rows = [
      { id: "design", text: "design", tree: "MASTER", kind: "design", scope_paths: ["MASTER/a.rb"] },
      { id: "cross", text: "cross", tree: "cross", kind: "mechanical", scope_paths: ["MASTER/a.rb", "RAILS/b.rb"] },
      { id: "operator", text: "operator", tree: "operator", kind: "operator-only", scope_paths: ["MASTER/a.rb"] },
    ]

    Dir.mktmpdir("backlog-executor") do |root|
      executor = Backlog::Executor.new(root:, repo_root: Backlog::MASTER_ROOT, mission_class: fake_mission)
      Backlog.stub(:generate, rows) { assert_equal :idle, executor.enqueue_next! }
    end
  end

  def test_executor_refuses_receipt_when_source_item_has_changed
    Dir.mktmpdir("backlog-executor") do |root|
      executor = Backlog::Executor.new(root:, repo_root: File.expand_path("..", Backlog::MASTER_ROOT))
      record = {
        "origin" => "backlog", "state" => "completed", "stage" => "deliver",
        "summary" => "proof complete", "artifacts" => [], "repository_writes" => {},
        "plan" => JSON.generate("executor" => "owner_registry", "item_id" => "x", "item_digest" => "digest"),
      }
      refute executor.record_completion!(record:)
      refute File.exist?(File.join(root, Backlog::Executor::RECEIPT_PATH))
    end
  end

  def test_executor_records_a_terminal_mission_receipt_only_for_the_current_item
    row = {
      id: "safe-task", text: "Repair the existing MASTER source and verify it.",
      tree: "MASTER", kind: "mechanical", scope_paths: ["MASTER/lib/example.rb"],
      done_when: "rake test", size: "s", section: "MASTER",
    }

    Dir.mktmpdir("backlog-executor") do |root|
      executor = Backlog::Executor.new(root:, repo_root: File.expand_path("..", Backlog::MASTER_ROOT))
      proof_types = Backlog::ProofMap.types_for(row)
      plan = {
        "executor" => "owner_registry",
        "item_id" => row.fetch(:id),
        "item_digest" => executor.send(:item_digest, row),
        "tree" => row.fetch(:tree),
        "done_when" => row.fetch(:done_when),
        "proof_map_version" => Backlog::ProofMap::VERSION,
        "proof_types" => proof_types,
        "journey" => {
          "route_id" => executor.send(:item_digest, row),
          "phase" => "tree_acceptance",
          "tree" => "MASTER",
          "objective" => Backlog::Executor::MISSION_OBJECTIVE,
          "priority" => 0.78,
          "score" => 1.25,
          "reason" => "grounded TODO, scope and allowlisted command",
          "exploration" => false,
          "alternatives" => [],
        },
      }
      record = {
        "origin" => "backlog", "state" => "completed", "stage" => "deliver",
        "summary" => "proof complete; focused tests passed and pushed",
        "finished_at" => Time.now.utc.iso8601,
        "artifacts" => [], "repository_writes" => {},
        "proof" => {
          "kind" => "fix_pipeline", "status" => "pass",
          "proof_map_version" => Backlog::ProofMap::VERSION,
          "required_proof_types" => proof_types,
          "scope_paths" => ["MASTER/lib/example.rb"],
          "report_digest" => "a" * 64,
          "proof_summary" => "fix done - 1 commit delivered - proof: 12 of 12 - hard red 0",
          "command_evidence" => {
            "proof_type" => "full_suite", "status" => "pass", "exit_status" => 0,
            "command_digest" => Digest::SHA256.hexdigest("rake test"),
            "output_digest" => "c" * 64, "output_bytes" => 128,
            "cwd" => "MASTER", "duration_ms" => 1200,
          },
        },
        "repository_pushes" => [
          { "remote" => "origin", "branch" => "main", "commit" => "b" * 40, "pushed_at" => Time.now.utc.iso8601 },
        ],
        "id" => "mission-1", "plan" => JSON.generate(plan.merge("scope_paths" => ["MASTER/lib/example.rb"])),
      }

      Backlog.stub(:generate, [row]) do
        missing_command = Marshal.load(Marshal.dump(record))
        missing_command.fetch("proof").delete("command_evidence")
        refute executor.record_completion!(record: missing_command)

        stale_command = Marshal.load(Marshal.dump(record))
        stale_command.fetch("proof").fetch("command_evidence")["command_digest"] = "d" * 64
        refute executor.record_completion!(record: stale_command)

        stale_journey = Marshal.load(Marshal.dump(record))
        stale_plan = JSON.parse(stale_journey.fetch("plan"))
        stale_plan.fetch("journey")["priority"] = 1.0
        stale_journey["plan"] = JSON.generate(stale_plan)
        refute executor.record_completion!(record: stale_journey)

        assert executor.record_completion!(record:)
        assert executor.record_completion!(record:)

        # Receipt validation re-reads the current TODO owner. Keep the fixture
        # row installed until both the receipt and its learning projection are
        # checked; outside this stub, "safe-task" is not a real TODO item.
        receipts = File.readlines(File.join(root, Backlog::Executor::RECEIPT_PATH)).map { |line| JSON.parse(line) }
        assert_equal 1, receipts.length
        receipt = receipts.first
        assert_equal "safe-task", receipt.fetch("item_id")
        assert_equal "verified_fix_pipeline_acceptance_and_origin_main", receipt.fetch("proof_status")
        assert_equal 0, receipt.dig("evidence", "pending_repository_writes")
        assert_equal "fix_pipeline", receipt.dig("proof", "kind")
        assert_equal "origin", receipt.dig("repository_pushes", 0, "remote")
        history = executor.send(:verified_route_history)
        assert_equal 1, history.size
        assert_equal plan.fetch("item_digest"), history.first.fetch("route_id")
        assert_equal "PASS", history.first.fetch("status")
        assert_equal "a" * 64, history.first.fetch("evidence_id")
      end
    end
  end

end
