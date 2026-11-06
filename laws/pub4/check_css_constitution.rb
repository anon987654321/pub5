# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml css_constitution by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bb64887e5beb598f
require_relative "master/lib/master"

Law.define(:CHECK_CSS_CONSTITUTION) do
  source "pub4 MASTER/checks/checks.yml css_constitution"
  practice "Check css_constitution holds: CSS constitution check passed (all stylesheets)."
end
