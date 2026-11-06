# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:379 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 85134d6490a1421d
require_relative "master/law/practice"

Law.define(:NO_NEW_FILES) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    edit the original path. No _fixed.rb, no staging copy, no new file without
    approval - try merge or rename first on every touch. Tree-level /fix checks
    the name and ownership surface before it creates a new path.
  TEXT
  fix "edit the original path."
  bad  "writes thing_fixed.rb"
  good "edits thing.rb"
end
