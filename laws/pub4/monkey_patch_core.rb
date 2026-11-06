# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:466 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 19f9cc935fb7b793
require_relative "master/law/ruby"

Law.define(:MONKEY_PATCH_CORE) do
  source "Polished Ruby Programming, 2nd ed. (Jeremy Evans, 2026) - core class hygiene"
  detect { |line| line.match?(/\A\s*class\s+(?:String|Array|Hash|Integer|Float|Symbol|Object|Kernel|NilClass|Numeric|Range|Time|Comparable|Enumerable)\s*\z/) }
  fix "Use a refinement, a helper module, or a wrapping method instead of reopening the core class."
  bad  "class String"
  good "module StringHelpers"
end
