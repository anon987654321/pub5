# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:334 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e8ff510fcb59e0a9
require_relative "master/law/ruby"

Law.define(:RUBY_SYMBOL_TO_PROC) do
  source "Ruby Style Guide / RuboCop Style/SymbolProc"
  detect { |line| line.match?(/\{\s*\|(\w+)\|\s*\1\.[a-z_]+\s*\}/) }
  fix "Collapse { |x| x.name } -> (&:name)."
  bad  "names = users.map { |u| u.name }"
  good "names = users.map(&:name)"
end
