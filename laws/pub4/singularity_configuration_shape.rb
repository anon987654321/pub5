# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SINGULARITY_configuration_shape by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5e76742f5230440e
require_relative "master/lib/master"

Law.define(:SINGULARITY_CONFIGURATION_SHAPE) do
  source "pub4 MASTER/data/laws.yml SINGULARITY_configuration_shape"
  practice "A config that reads as a program."
end
