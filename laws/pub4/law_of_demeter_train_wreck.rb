# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LAW_OF_DEMETER_train_wreck by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: be6e3607468e58fe
require_relative "master/lib/master"

Law.define(:LAW_OF_DEMETER_TRAIN_WRECK) do
  source "pub4 MASTER/data/laws.yml LAW_OF_DEMETER_train_wreck"
  practice "A chain of accessors that traverses more than one intermediary."
end
