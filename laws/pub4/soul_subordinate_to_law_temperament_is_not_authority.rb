# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SOUL_SUBORDINATE_TO_LAW_temperament_is_not_authority by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6360eafc062bcf9e
require_relative "master/lib/master"

Law.define(:SOUL_SUBORDINATE_TO_LAW_TEMPERAMENT_IS_NOT_AUTHORITY) do
  source "pub4 MASTER/data/laws.yml SOUL_SUBORDINATE_TO_LAW_temperament_is_not_authority"
  practice "A persona, voice or delivery preference overrides Soul identity, preservation principles, source authority or an individual Law requirement."
end
