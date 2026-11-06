# frozen_string_literal: true

require_relative "fix_helper"

# Moved from pub4 MASTER/test/test_repair_loop_per_fix_commit.rb
# (c49347f2d6), test_fix_stop_ends_repairs.rb (ad91bab976),
# test_repair_loop_protected.rb (f8b848140b) and the autofix delivery test of
# test_fix_loop_committer.rb (a024dc8440).
class FixRepairTest < Minitest::Test
  include FixHelper

  def repair(world, model, run: RunStub.new, laws: [violation_law])
    refusals = Core::Ledger.new(File.join(world.manifest.root, "log/fix_refusals.jsonl"))
    Fix::Repair.new(run:, world:, model:, laws:, refusals:, writer: "operator", tests: ->(_) { [] })
  end

  def seeded(root, files = { "a.rb" => "x = 1\nviolation = 2\n" })
    files.each { |path, text| put(root, path, text) }
    commit_all(root)
  end

  def findings(path = "a.rb") = [finding(:TEST_VIOLATION, 2, file: path)]

  def test_a_clean_repair_lands_as_one_commit_in_the_house_format
    repo do |root|
      seeded(root)
      world = fix_world(root)
      outcome = repair(world, ScriptedModel.new(fenced("x = 1\nfine = 2\n"))).call("a.rb", findings)

      assert_equal :landed, outcome.status
      assert_equal "fine = 2\n", File.read(File.join(root, "a.rb")).lines.last
      message = git(root, "log", "-1", "--format=%B")
      assert_empty Fix::CommitMessage.problems(message)
      assert_match(/^Law: TEST_VIOLATION$/, message)
    end
  end

  # The committer refusing a verified repair left the model's edit in the file.
  def test_a_repair_the_commit_hook_refuses_is_put_back_and_logged
    repo do |root|
      seeded(root)
      put(root, ".git/hooks/pre-commit", "#!/bin/sh\necho 'house lint: a.rb:1' >&2\nexit 1\n")
      File.chmod(0o755, File.join(root, ".git/hooks/pre-commit"))
      outcome = repair(fix_world(root), ScriptedModel.new(fenced("x = 1\nfine = 2\n"))).call("a.rb", findings)

      assert_equal :commit_refused, outcome.status
      assert_equal "x = 1\nviolation = 2\n", File.read(File.join(root, "a.rb"))
      assert_empty git(root, "status", "--porcelain")
      row = JSON.parse(File.read(File.join(root, "log/fix_refusals.jsonl")).lines.last)
      assert_equal %w[commit restored], row.values_at("stage", "outcome")
      assert_includes row["reason"], "house lint"
    end
  end

  # A file someone changed after the repair wrote it is theirs, and stays.
  def test_a_refused_repair_another_writer_changed_since_is_left
    repo do |root|
      seeded(root)
      put(root, ".git/hooks/pre-commit", "#!/bin/sh\nprintf 'someone else\\n' > a.rb\nexit 1\n")
      File.chmod(0o755, File.join(root, ".git/hooks/pre-commit"))
      outcome = repair(fix_world(root), ScriptedModel.new(fenced("x = 1\nfine = 2\n"))).call("a.rb", findings)

      assert_equal :commit_refused, outcome.status
      assert_equal "someone else\n", File.read(File.join(root, "a.rb"))
    end
  end

  def test_a_failing_mapped_test_puts_the_repair_back
    repo do |root|
      seeded(root, "lib/a.rb" => "x = 1\nviolation = 2\n", "test/a_test.rb" => "exit 1\n")
      world = fix_world(root)
      refusals = Core::Ledger.new(File.join(root, "log/fix_refusals.jsonl"))
      fixer = Fix::Repair.new(run: RunStub.new(tracked: ["lib/a.rb", "test/a_test.rb"]), world:, laws: [violation_law],
                              model: ScriptedModel.new(fenced("x = 1\nfine = 2\n")), refusals:, writer: "operator")
      outcome = fixer.call("lib/a.rb", findings("lib/a.rb"))

      assert_equal :refused, outcome.status
      assert_match(/test test\/a_test.rb failed/, outcome.reason)
      assert_equal "x = 1\nviolation = 2\n", File.read(File.join(root, "lib/a.rb"))
    end
  end

  # The stall guard said STOPPING, yet the loop kept asking for 40 minutes.
  def test_a_stopping_run_asks_no_model
    repo do |root|
      seeded(root)
      model = ScriptedModel.new(fenced("fine\n"))
      outcome = repair(fix_world(root), model, run: RunStub.new(stopping: "stalled, no yield")).call("a.rb", findings)

      assert_equal :stopped, outcome.status
      assert_empty model.prompts
    end
  end

  # A model repair of a protected file stopped a run forty minutes in.
  def test_a_protected_file_is_skipped_before_any_model_is_asked
    repo do |root|
      seeded(root, "registry/apps.yml" => "violation: 1\n")
      model = ScriptedModel.new(fenced("fine: 1\n"))
      outcome = repair(fix_world(root), model).call("registry/apps.yml", findings("registry/apps.yml"))

      assert_equal :skip_protected, outcome.status
      assert_empty model.prompts
    end
  end

  # Core's write verb holds the line even for a writer that skips the check.
  def test_core_refuses_the_write_of_a_protected_path
    repo do |root|
      seeded(root, "registry/apps.yml" => "violation: 1\n")
      assert_raises(Core::Refusal) { fix_world(root).write("registry/apps.yml", "fine: 1\n") }
      assert_equal "violation: 1\n", File.read(File.join(root, "registry/apps.yml"))
    end
  end

  # A refused proposal is retried once, with the refusal in the prompt.
  def test_a_refused_proposal_is_retried_with_its_reason
    repo do |root|
      seeded(root)
      model = ScriptedModel.new(fenced("x = (\nviolation = 2\n"), fenced("x = (\nviolation = 2\n"),
                                fenced("x = 1\nfine = 2\n"))
      outcome = repair(fix_world(root), model).call("a.rb", findings)

      assert_equal :landed, outcome.status
      assert_includes model.prompts.last, "Your previous proposal was refused: does not parse"
    end
  end

  def test_the_observations_autofix_writes_deliver_with_the_pass
    repo do |root|
      seeded(root, "AGENTS.md" => "# Agents   \n\nRead this.\n", "b.rb" => "y = 2  \n")
      world = fix_world(root)
      law = trailing_whitespace_law
      found = %w[AGENTS.md b.rb].map { |path| finding(:TRAILING_WHITESPACE, 1, file: path) }
      writes = Fix::Autofix.run(world, found, laws: [law])
      put(root, "b.rb", "y = 3\n")
      ours, left = writes.split(world)

      assert_equal ["AGENTS.md"], ours.map(&:path)
      assert_equal ["b.rb"], left.map(&:path), "a file changed since the autofix wrote it is someone else's"
    end
  end

  def trailing_whitespace_law
    builder = Law::Builder.new(:TRAILING_WHITESPACE)
    builder.instance_eval do
      check { |src, _| src.each_line.with_index(1).filter_map { |l, n| finding(line: n) if l.match?(/[ \t]+\n?\z/) } }
      bad "a  \n"
      good "a\n"
    end
    builder.build("autofix" => "automatic").prove!
  end
end
