# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:509 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f1154e1c34cb7a15
require_relative "master/law/ruby"

Law.define(:FILTER_MAP) do
  source "Fowler, Refactoring, 2nd ed. (2018) - Replace Loop with Pipeline"
  # \b after compact so compact_blank, a different operation with no
  # filter_map twin, does not fire.
  detect { |line| line.match?(/\.map\s*(?:\{[^}]*\}|&:[\w!?]+)\s*\.compact\b/) }
  fix "Collapse map { }.compact into filter_map { } - one pass, no nil detour."
  bad  "ids = items.map { |i| i.external_id }.compact"
  good "ids = items.filter_map { |i| i.external_id }"
end
