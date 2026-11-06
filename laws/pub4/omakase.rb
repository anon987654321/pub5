# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:419 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 753ad20e3a4d14fe
require_relative "master/law/universal"

Law.define(:OMAKASE) do
  source "The Menu Is Omakase (Rails Doctrine, DHH)"
  ask "Does this introduce a competing tool when the application already has a suitable integrated default?"
  fix "Use the existing integrated default unless a concrete requirement justifies deviation."
  bad <<~'X'
    require "external_queue"
  X
  good <<~'X'
    Rails.application.config.active_job.queue_adapter = :solid_queue
  X
end
