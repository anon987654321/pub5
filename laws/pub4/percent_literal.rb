# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:200 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 19e3587e4e24766c
require_relative "master/law/ruby"

Law.define(:PERCENT_LITERAL) do
  source "Ruby Style Guide - %w/%i array literals"
  detect { |line| line.match?(/\[:[a-z_]+,\s*:[a-z_]+,\s*:[a-z_]+/) }
  fix "Use %i[a b c] for symbol arrays."
  bad  "[:a, :b, :c]"
  good "%i[a b c]"
end
