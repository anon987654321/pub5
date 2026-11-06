# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BRINGHURST_alignment by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 664bc010bedf83b8
require_relative "master/lib/master"

Law.define(:BRINGHURST_ALIGNMENT) do
  source "pub4 MASTER/data/laws.yml BRINGHURST_alignment"
  practice "Prose justified or space-padded into a fake table."
end
