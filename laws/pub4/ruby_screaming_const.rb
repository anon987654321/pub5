# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:348 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5cf45145c3b05a41
require_relative "master/law/ruby"

Law.define(:RUBY_SCREAMING_CONST) do
  source "Ruby Style Guide / RuboCop Naming/ConstantName"
  ask "Is a Ruby value constant named in a case other than SCREAMING_SNAKE_CASE?"
  detect do |line|
    match = line.match(/^\s*([A-Z][A-Za-z0-9]*)\s*=(?!=|~|>)\s*(.*)$/)
    next false unless match && match[1].match?(/[a-z]/)
    next false if match[2].match?(/\A(Struct\.new|Data\.define|Class\.new|Module\.new)/)

    !match[2].match?(/\A[A-Z][\w:]*\s*\z/)
  end
  fix "Scream a constant that holds a value: MaxRetries = 3 -> MAX_RETRIES = 3."
  bad  "MaxRetries = 3"
  good "MAX_RETRIES = 3"
end
