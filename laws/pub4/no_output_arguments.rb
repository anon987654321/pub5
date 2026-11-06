# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1591 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8154815f3c62143f
require_relative "master/law/universal"

Law.define(:NO_OUTPUT_ARGUMENTS) do
  source "Clean Code - no output arguments"
  ask "Does this function mutate an input argument to return a result indirectly?"
  fix "Return the result explicitly instead of using output parameters."
  bad <<~'X'
    def normalize!(input); input.replace(input.strip); end
  X
  good <<~'X'
    def normalize(input); input.strip; end
  X
end
