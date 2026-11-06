# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:18 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6aad9556051e5509
require_relative "master/law/css"

Law.define(:LOGICAL_PROPERTIES) do
  source "CSS Logical Properties and Values (W3C)"
  detect { |line| line.match?(/(margin|padding)-(left|right):/) }
  fix "Use margin-inline-start/end, padding-inline-start/end."
  bad  "margin-left: 8px;"
  good "margin-inline-start: 8px;"
end
