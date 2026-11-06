# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:337 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fc091f569d149062
require_relative "master/law/universal"

Law.define(:NO_CHANGELOG_COMMENT) do
  source "MASTER-native - git holds history; comments hold reasons"
  reads_comments true
  detect do |line|
    line.match?(/^\s*(?:#|\/\/|\*)\s*(?:RAISED|RATCHETED|LOWERED|BUMPED|TRIMMED|UPDATED?|RENAMED|MOVED|CHANGED|REVERTED|REMOVED|ADDED|DEPRECATED|NARROWED|REDUCED|FIXED)\b[^\n]{0,40}\d{4}-\d{2}-\d{2}/i) ||
      line.match?(/^\s*(?:#|\/\/|\*)[^\n]{0,60}\b(?:used to be|was previously|were previously|formerly)\b/i) ||
      line.match?(/^\s*(?:#|\/\/|\*)[^\n]{0,60}\bchanged from\b[^\n]{0,40}\bto\b/i)
  end
  fix "State the present reason. Put the history in the commit message."
  bad "# RENAMED 2026-08-25 from Foo to Bar"
  good "# Bar names what it returns, so a caller can tell it from Baz."
end
