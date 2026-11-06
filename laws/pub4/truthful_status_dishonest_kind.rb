# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml TRUTHFUL_STATUS_dishonest_kind by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: be4101899875b042
require_relative "master/lib/master"

Law.define(:TRUTHFUL_STATUS_DISHONEST_KIND) do
  source "pub4 MASTER/data/laws.yml TRUTHFUL_STATUS_dishonest_kind"
  practice "A file's declared kind does not match its content."
end
