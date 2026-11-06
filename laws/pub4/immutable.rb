# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:115 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e1e3fd6dca096d58
require_relative "master/law/ruby"

Law.define(:IMMUTABLE) do
  source "Effective Java - minimize mutability (Joshua Bloch); FP"
  ask "Are mutable objects shared across threads or scopes where immutable data would be safer?"
  detect { |line| line.match?(/^\s*[A-Z][A-Z_]*\s*=\s*(?:\[[^\]\n]*\]|\{[^}\n]*\})\s*$/) }
  fix "Freeze collections. Use frozen/const by default."
  bad  "COLORS = [:red, :blue]"
  good "COLORS = [:red, :blue].freeze"
end
