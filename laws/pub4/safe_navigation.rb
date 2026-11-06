# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:368 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b93c6bb3c23281ff
require_relative "master/law/ruby"

Law.define(:SAFE_NAVIGATION) do
  source "Ruby Style Guide / RuboCop Style/SafeNavigation"
  detect { |line| line.match?(/(\w+)\s*&&\s*\1\.\w+/) && !line.match?(/[!=<>]=|[<>]|\?\s*\w/) }
  fix "Rewrite to x&.foo&.bar"
  bad  "user && user.name"
  good <<~X
    user&.name
    ok if list && list.size > 3
  X
end
