# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/graph.rb:181 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ebd30d8f5a11bacc
require_relative "master/lib/master"

Law.define(:CO_CHANGE_COUPLING) do
  source "pub4 MASTER/law/graph.rb:181"
  practice "Files co-change with N+ peers across module boundaries - hidden coupling"
end
