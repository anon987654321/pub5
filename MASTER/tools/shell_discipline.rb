# frozen_string_literal: true

# The PreToolUse Bash hook Claude's settings.json points at. The dotfile holds
# no policy: the one list of commands a shell line may not run lives at
# MASTER/data/law_runtime.yml#zsh, and this file judges the command through
# Master::Io::GnuTextTools - the same lexer Io::Shell and the
# ZSH_NATIVE_PATTERNS Law ask, so the three readers cannot disagree about what
# a line runs. A quoted word, heredoc body or redirect target is data, so a
# commit message naming a banned tool passes while the tool itself refuses.
#
# Stdin is the harness's PreToolUse payload, read by hook_ruby.rb so a modern
# Ruby is guaranteed. A pass prints nothing and exits 0; a refusal prints the
# PreToolUse deny decision carrying the replacement the law's row names; a
# broken hook never blocks a shell call (fail-open, as hook_ruby.rb expects).

require "json"

command = begin
  JSON.parse($stdin.read).dig("tool_input", "command").to_s
rescue StandardError
  ""
end

require_relative "../lib/io/gnu_text_tools"

begin
  shell = Master::Io::GnuTextTools.load(File.expand_path("../data/law_runtime.yml", __dir__))
  names = shell.banned_in(command)
rescue StandardError
  exit 0
end
exit 0 if names.empty?

print JSON.generate(
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: shell.refusal(names)
  }
)
