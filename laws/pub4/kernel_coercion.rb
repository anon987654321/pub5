# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:124 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 55320d775de8d4e7
require_relative "master/law/ruby"

Law.define(:KERNEL_COERCION) do
  source "Ruby Style Guide - Integer()/Float() over to_i/to_f"
  # The `|| []` arm left. The fix line names one substitution — the explicit
  # nil-ternary — and `x || []` is not that: Array() splats a Hash into pairs
  # and wraps a String, so swapping it in is a behaviour change wherever the
  # value is not already an array or nil. The rule's own `good` fixture carries
  # two surviving `|| []` forms, which is the rule agreeing with itself.
  detect { |line| line.match?(/(\w+)\s*\.\s*nil\?\s*\?\s*\[\]\s*:\s*\1/) }
  fix "Use Array(x) instead of x.nil? ? [] : x"
  bad  "list.nil? ? [] : list"
  good <<~X
    Array(list)
    held = index[key] || [] << entry
    errors[key] ||= []
  X
end
