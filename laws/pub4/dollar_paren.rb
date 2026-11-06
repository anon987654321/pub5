# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/shell.rb:4 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5261ef669306b3c4
require_relative "master/law/shell"

Law.define(:DOLLAR_PAREN) do
  source "ShellCheck SC2006 - $() over backticks"
  # A backtick followed by a method call is Ruby, not shell. drain-jobs.sh and
  # prune-guests.sh both embed `ruby34 -e '...'` to read the load average, and
  # inside that the backticks are Ruby's own command substitution — where they
  # are correct and `$()` is not a thing. Shell never writes `` `cmd`.method ``,
  # so the chain is the tell, and it costs nothing a real finding would have.
  detect { |line| line.match?(/`[^`]+`/) && !line.match?(/`[^`]+`\s*\.\s*\w/) }
  fix "Use $(command) - nestable and readable."
  bad  "now=`date`"
  good "now=$(date)"
end
