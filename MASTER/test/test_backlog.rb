# frozen_string_literal: true

require "stringio"
require "tmpdir"
# test_helper first: bundler/setup must pin the bundle's date before yaml's
# psych can activate the default-gem date, later in, and split the bundle.
require_relative "test_helper"
require "yaml"
require "json"
require_relative "../tools/backlog"

# The backlog is the one machine-readable view of TODO.md's checkbox items:
# this file holds the generator to the source the way the tools hold the
# tools to theirs — one row per unchecked item, stable ids, a done-where a
# command is named, and a check that fails the day the pair drifts.
class TestBacklog < Minitest::Test
  # A span that reads as a runnable command, and the prose verb that makes it
  # one: spans are read backtick-pair by backtick-pair, exactly the way the
  # prose is written, so prose sitting between two code spans is never
  # mistaken for one. Restated apart from the tool so a broken extraction
  # cannot grade itself green.
  COMMAND_SPAN = %r{\b(?:bundle exec|rake \w|\bruby \b|\bnode \b|pfctl|cd [A-Z]|(?:MASTER|OPENBSD)/bin/\w)}
  PROSE_RUN = /
    \b(?:run(?:s|ning)?|ran|re-?run|execut(?:e|es|ed)|verif(?:y|ies|ied)|
    validat(?:e|es|ed)|measur\w*|audit\w*|refresh\w*|captur\w*)\b
  /xi

  def entries
    @rows ||= Backlog.generate
  end

  def silent = StringIO.new

  def named_command?(text)
    text.scan(/`([^`\n]+)`/).flatten.any? { |span| span.match?(COMMAND_SPAN) }
  end

  def test_one_entry_per_unchecked_checkbox
    pub5 = false
    rows = 0
    File.foreach(Backlog::SOURCE) do |line|
      pub5 = true if line.start_with?("## pub5")
      rows += 1 if !pub5 && line.match?(/\A- \[ \]/)
    end

    # A pub5 plan section folds its checkboxes into one gated entry; without
    # one, every unchecked checkbox is its own row.
    expected = pub5 ? rows + 1 : rows
    assert_equal expected, entries.size
  end

  def test_ids_are_stable_across_reads_and_unique
    first = entries.map { |row| row[:id] }
    second = entries.map { |row| row[:id] }

    assert_equal first, second
    assert_equal first.size, first.uniq.size
  end

  def test_text_and_section_are_present_on_every_row
    entries.each do |row|
      assert_kind_of String, row[:id]
      refute_empty row[:text]
      refute_empty row[:section]
      assert_kind_of Array, row[:scope_paths]
    end
  end

  def test_tree_kind_and_size_stay_in_the_registered_vocabularies
    entries.each do |row|
      assert_includes Backlog::TREES, row[:tree]
      assert_includes Backlog::KINDS, row[:kind]
      assert_includes Backlog::SIZES, row[:size]
    end
  end

  def test_biz_paths_are_owned_and_captured_as_biz
    text = "Render and inspect BIZ/ragnhild/ragnhild_legater.html for pagination."
    item = { prose: [text], code: [], h1: "pub5", h2: "pub5 migration record", h3: nil }
    section = "pub5 — pub5 migration record"

    assert_includes Backlog::TREES, "BIZ"
    assert_equal "BIZ", Backlog.owner(item:, text:, section:, kind: "mechanical")
    assert_includes Backlog.scope_paths(text), "BIZ/ragnhild/ragnhild_legater.html"
  end

  def test_done_when_and_its_reason_never_both_speak
    entries.each do |row|
      if row[:done_when]
        assert_nil row[:done_when_note]
        refute_empty row[:done_when]
      else
        refute_empty row[:done_when_note], "row #{row[:id]} names no done_when and no reason"
      end
    end
  end

  def test_the_operator_seam_rows_are_operator_only
    seams = entries.select { |row| row[:section].include?("8.5 Operator-only") }

    refute_empty seams, "the consolidated register carries one operator-seam section"
    assert(seams.all? { |row| row[:kind] == "operator-only" })
    assert(seams.all? { |row| row[:tree] == "operator" })
  end

  def test_no_other_row_claims_the_operator_tree
    assert_equal claimed_by_rule, claimed_by_tree
  end

  def test_done_when_covers_every_row_that_names_a_runnable_command
    entries.each do |row|
      next unless named_command?(row[:text]) && row[:text].match?(PROSE_RUN)

      refute_nil row[:done_when],
        "row #{row[:id]} names a runnable command but carries no done_when"
    end
  end

  def test_done_when_is_verbatim_from_the_baymard_gates_row
    gates = entries.find { |row| row[:text].include?("ux:baymard") }

    refute_nil gates
    assert_equal "rake lint:law_parity", gates[:done_when]
  end

  def test_the_installed_ruby_verification_row_names_its_command
    pinned = entries.find { |row| row[:text].include?("MASTER on the installed compatible Ruby") }

    refute_nil pinned
    assert_equal "rake test", pinned[:done_when].split(" ").last(2).join(" ")
  end

  def test_the_2026_11_04_intake_items_left_the_register
    generated = entries.find { |row| row[:text].include?("generated from this file") }
    done_when = entries.find { |row| row[:text].include?("machine-checkable \"done when\"") }

    assert_nil generated, "the backlog generator landed; its intake rows are not work anymore"
    assert_nil done_when, "the done-when intake landed with the generator"
  end

  def test_pub5_is_one_plan_entry_gated_on_the_freeze_condition
    source_has_plan = File.foreach(Backlog::SOURCE).any? { |line| line.start_with?("## pub5") }
    plans = entries.select { |row| row[:kind] == "plan" }

    if source_has_plan
      assert_equal 1, plans.size
      assert_equal "cross", plans.first[:tree]
      assert_nil plans.first[:done_when]
      assert(plans.first[:done_when_note].include?("freeze"))
    else
      # The completed migration plan left the register; no orphan plan row
      # may outlive the section it was folded from.
      assert_empty plans
    end
  end

  def test_scope_paths_follow_the_paths_the_text_names
    gates = entries.find { |row| row[:text].include?("ux:baymard") }

    refute_nil gates, "the row that names MASTER/Rakefile must claim it as scope"
    assert(gates[:scope_paths].include?("MASTER/Rakefile"))
    refute(entries.any? { |row| row[:scope_paths].any? { |path| path.end_with?("/") } })
  end

  def test_sizes_grow_monotonically_with_text_length
    order = { "s" => 0, "m" => 1, "l" => 2 }
    ranks = entries.sort_by { |row| row[:text].length }.map { |row| order[row[:size]] }

    assert_equal ranks, ranks.sort
  end

  def test_check_passes_on_a_clean_checkout
    state = Dir.chdir(Backlog::MASTER_ROOT) do
      `git status --porcelain -- ../TODO.md data/backlog.yml`.strip
    end
    skip "TODO.md or data/backlog.yml is dirty in this checkout" unless state.empty?

    assert_equal 0, Backlog::Store.check(io: silent)
  end

  def test_check_flags_a_source_that_grew
    Dir.mktmpdir("backlog-check") do |dir|
      out = File.join(dir, "backlog.yml")
      assert_equal 0, Backlog::Store.write(out:, io: silent)

      drifted = File.join(dir, "todo.md")
      lines = File.readlines(Backlog::SOURCE)
      # The item enters above the first section heading: an item appended
      # after the last checkbox would change nothing and prove nothing.
      first_section = lines.index { |line| line.start_with?("## ") }
      lines.insert(first_section, "- [ ] An item the source never carried.\n")
      File.write(drifted, lines.join)

      assert_equal 1, Backlog::Store.check(source: drifted, out:, io: silent)
    end
  end

  def test_write_refuses_a_row_whose_id_carries_changed_text
    Dir.mktmpdir("backlog-guard") do |dir|
      out = curate_first_row(dir)

      # The ids are derived from the text, so an id whose text moved is a hand
      # curation or a collision; either way the write stops.
      assert_equal 1, Backlog::Store.write(out:, io: silent)
    end
  end

  def test_write_refresh_replaces_the_curated_text
    Dir.mktmpdir("backlog-guard") do |dir|
      out = curate_first_row(dir)
      edited = YAML.load_file(out)["entries"].first["text"]

      assert_equal 0, Backlog::Store.write(out:, refresh: true, io: silent)
      refute_equal edited, YAML.load_file(out)["entries"].first["text"]
    end
  end

  def test_the_check_flags_a_hand_curated_field
    Dir.mktmpdir("backlog-curate") do |dir|
      out = File.join(dir, "backlog.yml")
      assert_equal 0, Backlog::Store.write(out:, io: silent)

      data = YAML.load_file(out)
      data["entries"].first["kind"] = "product"
      File.write(out, YAML.dump(data))

      assert_equal 1, Backlog::Store.check(out:, io: silent)
    end
  end


  def test_proof_map_covers_explicit_test_lint_and_runtime_commands
    map = Backlog::ProofMap

    assert_equal ["full_suite"], map.types_for(done_when: "rake test")
    assert_equal ["full_suite"], map.types_for(done_when: "cd MASTER && MASTER_TEST_JOBS=1 bundle exec rake test")
    assert_equal ["full_suite"], map.types_for(done_when: "ruby RAILS/test/run_all.rb")
    assert_equal ["full_suite"], map.types_for(done_when: "cd RAILS/brgen && bin/ci")
    assert_equal ["focused_tests"], map.types_for(done_when: "rake test:fix:convergence")
    assert_equal ["focused_tests"], map.types_for(done_when: "ruby -Itest test/test_fix_kernel.rb")
    assert_equal ["focused_tests"], map.types_for(done_when: "rspec spec/fix_spec.rb")
    assert_equal ["law_assessment"], map.types_for(done_when: "rake lint:law_parity")
    assert_equal ["law_assessment"], map.types_for(done_when: "rake audit")
    assert_equal ["law_assessment"], map.types_for(done_when: "ruby MASTER/checks/runner.rb --all")
    assert_equal ["rendered_evidence"], map.types_for(done_when: "MASTER/bin/operator visual sweep RAILS/brgen --one-page")
    assert_equal ["accessibility_review"], map.types_for(done_when: "bin/operator accessibility")
    assert_equal ["runtime_evidence"], map.types_for(done_when: "pfctl -nf /etc/pf.conf")
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
      executor = Backlog::Executor.new(root:, repo_root: Backlog::MASTER_ROOT)
      record = {
        "origin" => "backlog", "state" => "completed", "stage" => "deliver",
        "summary" => "proof complete", "artifacts" => [], "repository_writes" => {},
        "plan" => JSON.generate("executor" => "root_todo", "item_id" => "x", "item_digest" => "digest"),
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
      executor = Backlog::Executor.new(root:, repo_root: Backlog::MASTER_ROOT)
      plan = {
        "executor" => "root_todo",
        "item_id" => row.fetch(:id),
        "item_digest" => executor.send(:item_digest, row),
      }
      record = {
        "origin" => "backlog", "state" => "completed", "stage" => "deliver",
        "summary" => "proof complete; focused tests passed and pushed",
        "finished_at" => Time.now.utc.iso8601,
        "artifacts" => [], "repository_writes" => {},
        "proof" => {
          "kind" => "fix_pipeline", "status" => "pass",
          "scope_paths" => ["MASTER/lib/example.rb"],
          "report_digest" => "a" * 64,
          "proof_summary" => "fix done - 1 commit delivered - proof: 12 of 12 - hard red 0",
        },
        "repository_pushes" => [
          { "remote" => "origin", "branch" => "main", "commit" => "b" * 40, "pushed_at" => Time.now.utc.iso8601 },
        ],
        "id" => "mission-1", "plan" => JSON.generate(plan.merge("scope_paths" => ["MASTER/lib/example.rb"])),
      }

      Backlog.stub(:generate, [row]) do
        assert executor.record_completion!(record:)
        assert executor.record_completion!(record:)
      end
      receipts = File.readlines(File.join(root, Backlog::Executor::RECEIPT_PATH)).map { |line| JSON.parse(line) }
      assert_equal 1, receipts.length
      receipt = receipts.first
      assert_equal "safe-task", receipt.fetch("item_id")
      assert_equal "verified_fix_pipeline_and_origin_main", receipt.fetch("proof_status")
      assert_equal 0, receipt.dig("evidence", "pending_repository_writes")
      assert_equal "fix_pipeline", receipt.dig("proof", "kind")
      assert_equal "origin", receipt.dig("repository_pushes", 0, "remote")
    end
  end


  private

  # The consolidated register marks one section (8.5) as operator seams by
  # heading; the classification honors that mark, restated here so a widened
  # OPERATOR_ONLY rule shows up as a tree-count mismatch.
  def claimed_by_rule
    entries.select { |row| row[:section].include?("8.5 Operator-only") }
           .map { |row| row[:id] }.uniq.sort
  end

  def claimed_by_tree
    entries.select { |row| row[:tree] == "operator" }.map { |row| row[:id] }.sort
  end

  def curate_first_row(dir)
    out = File.join(dir, "backlog.yml")
    assert_equal 0, Backlog::Store.write(out:, io: silent)

    data = YAML.load_file(out)
    data["entries"].first["text"] = "A deliberately edited row that TODO.md does not carry."
    File.write(out, YAML.dump(data))
    out
  end
end
