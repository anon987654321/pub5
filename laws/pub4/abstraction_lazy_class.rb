# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ABSTRACTION_lazy_class by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d5dfe1b270c76324
require_relative "master/lib/master"

Law.define(:ABSTRACTION_LAZY_CLASS) do
  source "pub4 MASTER/data/laws.yml ABSTRACTION_lazy_class"
  practice "A class that only stores attributes is a Hash with a costume."
end
