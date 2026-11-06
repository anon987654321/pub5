# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:431 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2b8be9032bb4306b
require_relative "master/law/universal"

Law.define(:NO_ONE_PARADIGM) do
  source "No One Paradigm (Rails Doctrine, DHH)"
  ask "Does this force one programming paradigm where a pragmatic combination would make the design clearer?"
  fix "Mix paradigms where each fits the problem; do not enforce uniformity for ideology's sake."
  bad <<~'X'
    class Pipeline; def call; steps.inject { |state, step| step.call(state) }; end; end
  X
  good <<~'X'
    steps.map(&:normalize).each { |step| persist(step) }
  X
end
