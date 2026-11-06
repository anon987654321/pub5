# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SRP_no_god_class by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fda1b1aa5bd171ff
require_relative "master/lib/master"

Law.define(:SRP_NO_GOD_CLASS) do
  source "pub4 MASTER/data/laws.yml SRP_no_god_class"
  practice "A class with one name and ten responsibilities."
end
