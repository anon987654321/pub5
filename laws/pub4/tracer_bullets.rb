# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:589 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ebda2975722e21c0
require_relative "master/law/universal"

Law.define(:TRACER_BULLETS) do
  source "The Pragmatic Programmer - tracer bullets"
  ask "Is infrastructure being built without first proving the simplest end-to-end path through the real system?"
  fix "Wire the smallest end-to-end path first, prove it works, then add depth."
  bad <<~'X'
    class Queue; end; class Worker; end; class Adapter; end
  X
  good <<~'X'
    result = adapter.call(input)
  X
end
