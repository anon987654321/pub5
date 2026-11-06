# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/shell.rb:114 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a01751b6bbbd6fd6
require_relative "master/law/shell"

Law.define(:ZSH_NATIVE_PATTERNS) do
  source "data/laws.yml zsh.banned_commands - Ruby and zsh, not GNU text tools"
  check do |text, file|
    zsh = text.match?(%r{\A#![^\n]*\bzsh\b}) || (file.end_with?(".zsh") && !text.start_with?("#!"))
    next [] unless zsh

    tools = Master::Io::GnuTextTools.new(Master.law("zsh"))
    lines = Master::Io::ShellLexer.blank_heredoc_bodies(text).lines
    lines.each_with_index.flat_map do |line, index|
      tools.banned_in(line).map do |name|
        finding(line: index + 1, message: "ZSH_NATIVE_PATTERNS: #{name} - use #{tools.replacement(name)}")
      end
    end
  end
  fix "Write the zsh expansion, glob or Ruby expression data/laws.yml names for the banned command."
  bad <<~X
    #!/usr/bin/env zsh
    count=$(wc -l < log)
  X
  good <<~X
    #!/usr/bin/env zsh
    lines=( ${(f)"$(<log)"} )
    print ${#lines}
  X
end
