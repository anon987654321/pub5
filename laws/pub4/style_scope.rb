# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STYLE_SCOPE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a0d4e3ab06df0014
require_relative "master/lib/master"

Law.define(:STYLE_SCOPE) do
  source "pub4 MASTER/data/laws.yml STYLE_SCOPE"
  practice "Reference-derived styles transfer only explicitly declared attribute classes, each with its own source fingerprint and strength."
end
