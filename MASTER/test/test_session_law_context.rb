# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "tmpdir"

# tools/session_law_context.rb puts the constitution in front of the agent at session start, and the three
# Claude Code hooks that mirror MASTER are registered in the committed settings.
class TestSessionLawContext < Minitest::Test
  HOOK = File.expand_path("../tools/session_law_context.rb", __dir__)
  REPO = File.expand_path("../..", __dir__)

  def run_hook(payload)
    out, status = Open3.capture2e(RbConfig.ruby, HOOK, stdin_data: JSON.generate(payload))
    [status.exitstatus, out]
  end

  def test_it_states_the_authority_order_and_the_lint_to_run
    code, out = run_hook({ "cwd" => File.join(REPO, "MASTER") })

    assert_equal 0, code
    # The authority order is stated by tier id, and the two file tiers it names
    # are also given as paths: an agent that reads only ids still finds the
    # constitution, and the order is read from soul.yml rather than typed twice.
    authority = Master::Soul.authority_order(root: REPO).map { |row| row.fetch("id") }
    assert_includes out, "Source authority (highest first): #{authority.join(' > ')}."
    assert_includes out, "read MASTER/data/soul.yml for identity"
    assert_includes out, "read MASTER/data/laws.yml for the Law records"
    assert_includes out, "One hook refuses tool calls"
    assert_includes out, "lint --changed-lines"
    assert_includes out, "Governing invariant Laws (laws.yml document order):"
    assert_match(/^  \d+\. [A-Z_]+: \S/, out, "the top-ranked laws are listed from laws.yml")
  end

  def test_it_is_silent_outside_a_checkout
    Dir.mktmpdir do |dir|
      code, out = run_hook({ "cwd" => dir })

      assert_equal 0, code
      assert_empty out
    end
  end

  def settings = JSON.parse(File.read(File.join(REPO, ".claude", "settings.json"))).fetch("hooks")

  def registered_commands
    settings.values.flatten.flat_map { |entry| entry.fetch("hooks") }.map { |hook| hook.fetch("command") }
  end

  # The briefing runs through hook_ruby.rb, which finds a Ruby that can parse it when the hook's PATH
  # holds only 2.6. One hook refuses tool calls: the PreToolUse shell-discipline gate refuses what
  # the zsh law bans (operator, 2026-11-08); every other registered hook adds context or speech and
  # refuses nothing.
  def test_the_committed_settings_brief_the_session_and_refuse_only_banned_shell
    commands = registered_commands

    assert(commands.any? { |command| command.end_with?("hook_ruby.rb\" session_law_context") }, commands.inspect)
    assert_empty commands.grep(%r{MASTER/tools/(?!hook_ruby)\w+\.rb}), "no hook bypasses the launcher"

    pre = settings.fetch("PreToolUse")
    pre_hooks = pre.flat_map { |entry| entry.fetch("hooks") }
    assert(pre_hooks.any? { |hook| hook.fetch("command").end_with?("shell_discipline") },
           "the refusing hook judges through the zsh law: #{pre_hooks.inspect}")
    refusing = commands.count { |command| command.end_with?("shell_discipline") }
    assert_equal 1, refusing, "exactly one hook refuses, and it judges the zsh law: #{commands.inspect}"
  end
end
