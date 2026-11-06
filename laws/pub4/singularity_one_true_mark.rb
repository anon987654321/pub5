# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SINGULARITY_one_true_mark by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fce6f2f1b6a6317e
require_relative "master/lib/master"

Law.define(:SINGULARITY_ONE_TRUE_MARK) do
  source "pub4 MASTER/data/laws.yml SINGULARITY_one_true_mark"
  practice "Two marks for one meaning."
end
