# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml TRUTHFUL_STATUS_hidden_system_status by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: afe7b10ea81245bd
require_relative "master/lib/master"

Law.define(:TRUTHFUL_STATUS_HIDDEN_SYSTEM_STATUS) do
  source "pub4 MASTER/data/laws.yml TRUTHFUL_STATUS_hidden_system_status"
  practice "The system does not tell the reader what it is doing in time to be useful."
end
