# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:276 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4293b3a71fdb0f96
require_relative "master/law/ruby"

Law.define(:RUBY_BLOCK_DELIMITER) do
  source "Ruby Style Guide / RuboCop Style/BlockDelimiters"
  detect { |line| line.match?(/\bdo\b\s*(\|[^|]*\|)?[^\n]*\bend\s*$/) }
  fix "Single-line block on one line -> use { }. Reserve do/end for multi-line."
  bad  "list.each do |x| puts x end"
  good "list.each { |x| puts x }"
end
