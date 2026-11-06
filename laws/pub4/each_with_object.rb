# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:8 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 44796b4d48a4ed27
require_relative "master/law/ruby"

Law.define(:EACH_WITH_OBJECT) do
  source "Ruby Style Guide / RuboCop Style/EachWithObject"
  detect { |line| line.match?(/\.(inject|reduce)\(\s*(\{\s*\}|\[\s*\])\s*\)/) }
  fix "Only when the argument is a literal {} or [] that the block mutates in place. Do NOT rewrite reduce/inject whose block returns the next accumulator (a rebuilt string, a running total, a folded hash) - each_with_object discards that return value and the fold becomes a no-op. If in doubt, leave reduce alone."
  bad  "items.inject({}) { |h, i| h[i] = 1; h }"
  good "items.each_with_object({}) { |i, h| h[i] = 1 }"
end
