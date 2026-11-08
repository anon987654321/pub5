# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

# The Claude Code PreToolUse hook is wiring, not policy: the dotfile points at
# MASTER/tools/shell_discipline.rb, and that file judges through the one list
# at MASTER/data/law_runtime.yml#zsh. These tests run the hook the way the
# harness runs it - a JSON payload on stdin, an exit that decides - and hold
# the command/data line the retired inline-list hook lost.
class HookShellDisciplineTest < Minitest::Test
  HOOK = File.join(Master::ROOT, "tools", "shell_discipline.rb").freeze

  def decision(command, stdin_data: nil)
    payload = stdin_data || JSON.generate(tool_name: "Bash", tool_input: { command: command })
    out, _err, status = Open3.capture3(RbConfig.ruby, HOOK, stdin_data: payload)
    verdict = if status.success?
      out.empty? ? nil : JSON.parse(out).dig("hookSpecificOutput", "permissionDecision")
    else
      "crashed"
    end
    [verdict, out]
  end

  def test_a_piped_banned_tool_is_refused_and_named_with_its_owner
    verdict, out = decision("git log --oneline | head -5")
    assert_equal "deny", verdict
    assert_match(/head: /, out)
    assert_match(/law_runtime\.yml zsh\.banned_commands/, out)
  end

  def test_a_banned_command_in_quoted_data_passes
    # Io::Shell once warned and ran on this shape; the lexer calls quoted words data.
    verdict, out = decision('git commit -m "drop the tail call"')
    assert_nil verdict, out
  end

  def test_nested_shells_wrappers_and_assignments_reach_the_real_command
    assert_equal "deny", decision('zsh -c "wc -l f"').first
    assert_equal "deny", decision("xargs sed -i s/a/b/ f").first
    assert_equal "deny", decision("FOO=1 awk '{print $1}' f").first
    assert_equal "deny", decision("gsed -i s/a/b/ f").first
  end

  def test_clean_lines_pass_silent
    verdict, out = decision("ruby -e 'File.foreach(ARGV[0]).first(20)' f")
    assert_nil verdict
    assert_empty out
  end

  def test_broken_stdin_never_blocks_a_shell_call
    out, _err, code = Open3.capture3(RbConfig.ruby, HOOK, stdin_data: "not json")
    assert_predicate code, :success?
  end
end
