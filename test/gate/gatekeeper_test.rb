# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require_relative "../../master/commands/gate"

# bin/master gate over local fixtures: a bare origin, a seed clone the
# writers push from, and the gatekeeper's own clone. The fixture bin/check
# is the parse stage alone, so a run takes milliseconds.
class GatekeeperTest < Minitest::Test
  include TestHelper

  CHECK = <<~'RUBY'
    files = Dir.glob("**/*.rb")
    bad = files.filter_map do |file|
      RubyVM::InstructionSequence.compile(File.read(file))
      nil
    rescue SyntaxError => e
      "parse: #{file}: #{e.message.lines.first.strip}"
    end
    puts bad
    puts "parse: #{files.size} files, #{bad.size} broken"
    puts "check: #{bad.empty? ? 'ok' : 'FAILED'}"
    exit(bad.empty? ? 0 : 1)
  RUBY

  def fixture
    sandbox do |dir|
      @dir = dir
      @origin = File.join(dir, "origin.git")
      @seed = File.join(dir, "seed")
      @gate = File.join(dir, "gate")
      git(dir, "init", "-q", "--bare", "-b", "main", @origin)
      git(dir, "clone", "-q", @origin, @seed)
      identity(@seed, "gktepsta")
      put(@seed, "bin/check", CHECK)
      put(@seed, "rails/app.rb", "x = 1\n")
      @c1 = commit("Seed the fixture tree", writer: "claude")
      git(@seed, "push", "-q", "origin", "main")
      git(dir, "clone", "-q", @origin, @gate)
      identity(@gate, "pub5 gate")
      yield
    end
  end

  def git(dir, *args)
    run = tool.exec("git", "-C", dir, *args, unset: Gatekeeper::Repo::INHERITED)
    raise "git #{args.join(' ')}: #{run.err}" unless run.ok?

    run.out.strip
  end

  def tool = @tool ||= world(@dir, { exec: ["git"] }, name: "fixture")

  def identity(dir, name)
    git(dir, "config", "user.name", name)
    git(dir, "config", "user.email", "#{name.split.first}@example.org")
  end

  def commit(subject, writer: nil, author: nil, files: {})
    files.each { |path, text| put(@seed, path, text) }
    git(@seed, "add", "-A")
    message = writer ? "#{subject}\n\nWriter: #{writer}\n" : subject
    git(@seed, "commit", "-q", "-m", message, *(author ? ["--author", "#{author} <#{author}@users.noreply.github.com>"] : []))
    git(@seed, "rev-parse", "HEAD")
  end

  def push_main(subject, **options)
    sha = commit(subject, **options)
    git(@seed, "push", "-q", "origin", "main")
    sha
  end

  def push_branch(branch, subject, files:, writer:)
    git(@seed, "checkout", "-q", "-b", branch.tr("/", "-"), "origin/main")
    sha = commit(subject, writer:, files:)
    git(@seed, "push", "-q", "origin", "HEAD:refs/heads/#{branch}")
    git(@seed, "checkout", "-q", "main")
    sha
  end

  def gate(*argv, env: {})
    out = StringIO.new
    verbs = Core::Registry.load(:commands).dig("commands", "gate", "verbs")
    w = world(@gate, verbs, name: "gate", env:)
    code = Commands::Gate.new(world: w, context: "pipe", out:, knobs: knobs(env)).call(argv)
    [code, out.string]
  end

  def ledger(event) = Core::Ledger.new(File.join(@gate, "log/ledger.jsonl")).entries.select { |e| e["kind"] == "gate" && e["event"] == event }

  def origin_main = git(@origin, "rev-parse", "main")

  def test_a_green_commit_passes_and_names_its_writer
    fixture do
      code, out = gate
      assert_equal 0, code, out
      verdict = ledger("verdict").last
      assert_equal [@c1, "PASS", "claude", "gktepsta"], verdict.values_at("sha", "result", "writer", "author")
      assert_match(/#{@c1[0, 10]} PASS claude/, out)
      refute File.exist?(File.join(@gate, "log/gate/FAILED"))
    end
  end

  def test_unparseable_ruby_fails_with_its_author_and_leaves_a_marker
    fixture do
      gate
      bad = push_main("Break the parse", writer: "claude", files: { "rails/broken.rb" => "def broken(\n" })
      code, out = gate
      assert_equal 1, code
      verdict = ledger("verdict").last
      assert_equal [bad, "FAIL", "parse", "gktepsta"], verdict.values_at("sha", "result", "step", "author")
      assert_match %r{rails/broken\.rb}, verdict["detail"]
      assert_match(/\A#{bad} claude gktepsta parse/, File.read(File.join(@gate, "log/gate/FAILED")))
      assert_equal bad, origin_main, "auto-revert is off by default"
      push_main("Repair the parse", writer: "claude", files: { "rails/broken.rb" => "def broken; end\n" })
      assert_equal 0, gate.first
      refute File.exist?(File.join(@gate, "log/gate/FAILED")), "a green main clears the marker"
    end
  end

  def test_inbox_branches_merge_only_when_green_and_inside_the_writers_trees
    fixture do
      gate
      green = push_branch("inbox/glm", "Add a feature", writer: "glm", files: { "rails/feature.rb" => "y = 2\n" })
      red = push_branch("inbox/zai", "Add a broken file", writer: "zai", files: { "rails/bad.rb" => "class (\n" })
      outside = push_branch("inbox/grok", "Edit the registry", writer: "grok", files: { "registry/x.yml" => "a: 1\n" })
      code, out = gate
      assert_equal 0, code, out
      decisions = ledger("inbox").to_h { |e| [e["branch"], e] }
      assert_equal "merged", decisions.dig("inbox/glm", "decision")
      assert git_ok?("merge-base", "--is-ancestor", green, "main")
      assert_equal 2, git(@origin, "show", "-s", "--format=%P", "main").split.size
      assert_equal %w[left left], decisions.values_at("inbox/zai", "inbox/grok").map { |e| e["decision"] }
      assert_match(/bin\/check failed on the merge at parse/, decisions.dig("inbox/zai", "reason"))
      assert_match %r{outside grok's trees: registry/x\.yml}, decisions.dig("inbox/grok", "reason")
      refute git_ok?("merge-base", "--is-ancestor", red, "main")
      refute git_ok?("merge-base", "--is-ancestor", outside, "main")
      assert_equal origin_main, ledger("verdict").select { |v| v["ref"] == "main" }.last["sha"], "the merge is judged once, as it is merged"
    end
  end

  def git_ok?(*args) = tool.exec("git", "-C", @origin, *args, unset: Gatekeeper::Repo::INHERITED).ok?

  def test_an_inbox_tier_push_to_main_is_a_violation
    fixture do
      gate
      direct = push_main("Push past the inbox", writer: "chatgpt", files: { "rails/c.rb" => "z = 3\n" })
      shared = push_main("Push from the shared account", writer: "claude", author: "anon987654321",
                                                         files: { "rails/d.rb" => "w = 4\n" })
      code, out = gate
      assert_equal 1, code
      violations = ledger("violation")
      assert_equal [direct, shared], violations.map { |v| v["sha"] }
      assert_equal "chatgpt", violations.first["writer"]
      assert_match(/as anon987654321 \(inbox tier\)/, violations.last["reason"])
      assert_match(/violation #{direct[0, 10]} chatgpt/, out)
      assert_match(/2 violations/, out)
    end
  end

  def test_a_rewritten_main_is_a_violation_naming_both_tips
    fixture do
      gate
      git(@seed, "checkout", "-q", "--orphan", "other")
      git(@seed, "rm", "-rq", "--cached", ".")
      put(@seed, "rails/new.rb", "v = 5\n")
      git(@seed, "add", "bin/check", "rails/new.rb")
      git(@seed, "commit", "-q", "-m", "Replace the history\n\nWriter: claude\n")
      rewritten = git(@seed, "rev-parse", "HEAD")
      git(@seed, "push", "-q", "--force", "origin", "HEAD:refs/heads/main")
      code, out = gate
      assert_equal 1, code
      v = ledger("violation").last
      assert_equal ["force-push", @c1, rewritten], v.values_at("reason", "old", "new")
      assert_match(/main rewritten/, out)
      assert_equal 1, gate.first.then { ledger("violation").size }, "one rewrite is recorded once"
    end
  end

  def test_a_second_run_is_a_no_op
    fixture do
      gate
      push_branch("inbox/zai", "Add a broken file", writer: "zai", files: { "rails/bad.rb" => "class (\n" })
      gate
      before = Core::Ledger.new(File.join(@gate, "log/ledger.jsonl")).entries.count { |e| e["kind"] == "gate" }
      code, out = gate
      assert_equal 0, code
      assert_match(/nothing new/, out)
      assert_equal before, Core::Ledger.new(File.join(@gate, "log/ledger.jsonl")).entries.count { |e| e["kind"] == "gate" }
      _, status = gate("--status")
      assert_match(/#{@c1[0, 10]} PASS claude/, status)
      assert_match(%r{inbox/zai \h+ left}, status)
    end
  end

  def test_an_overlapping_run_skips
    fixture do
      git(@gate, "update-ref", "refs/gate/lock", "HEAD")
      code, out = gate
      assert_equal 0, code
      assert_match(/skipped, locked/, out)
      assert_empty ledger("verdict")
      git(@gate, "update-ref", "-d", "refs/gate/lock")
      gate
      refute git_ok_in(@gate, "rev-parse", "--verify", "-q", "refs/gate/lock"), "a run releases the lock"
    end
  end

  def git_ok_in(dir, *args) = tool.exec("git", "-C", dir, *args, unset: Gatekeeper::Repo::INHERITED).ok?

  def test_auto_revert_reverts_the_commit_that_broke_a_green_main
    fixture do
      env = { "PUB5_GATE_AUTO_REVERT" => "1" }
      gate(env:)
      bad = push_main("Break the parse", writer: "claude", files: { "rails/broken.rb" => "def broken(\n" })
      _, out = gate(env:)
      assert_match(/reverted #{bad[0, 10]}/, out)
      message = git(@origin, "show", "-s", "--format=%B", "main")
      assert_match(/\ARevert #{bad[0, 10]} after it failed the gate/, message)
      assert_includes message, "This reverts commit #{bad}"
      assert_equal git(@origin, "rev-parse", "#{@c1}^{tree}"), git(@origin, "rev-parse", "main^{tree}"), "the revert restores the green tree"
      code, = gate(env:)
      assert_equal 0, code, "the revert commit is judged green"
    end
  end
end
