# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:407 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3670e5ef701de33b
require_relative "master/law/universal"

Law.define(:PROGRAMMER_HAPPINESS) do
  source "Optimize for Programmer Happiness (Rails Doctrine, DHH)"
  ask "Does this design impose ceremony or friction that does not buy meaningful safety or clarity?"
  fix "Remove unnecessary ceremony and keep the common path expressive."
  bad <<~'X'
    builder = RequestBuilder.new; builder.configure { |x| x.timeout = 30 }; builder.build
  X
  good <<~'X'
    request = Request.new(timeout: 30)
  X
end
