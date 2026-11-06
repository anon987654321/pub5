# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:379 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8e5845265273837e
require_relative "master/law/ruby"

Law.define(:SINGLE_PRIVATE_SECTION) do
  source "Ruby Style Guide / RuboCop Style/AccessModifierDeclarations"
  detect { |line| line.match?(/private\s+:\w+/) }
  fix "Use a single 'private' keyword with methods below it."
  bad  "private :helper"
  good <<~X
    private

    def helper; end
  X
end
