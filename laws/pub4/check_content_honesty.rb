# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml content_honesty by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 83ed46636c39d0fc
require_relative "master/lib/master"

Law.define(:CHECK_CONTENT_HONESTY) do
  source "pub4 MASTER/checks/checks.yml content_honesty"
  practice "Check content_honesty holds: Content honesty check passed (no Faker filler on public surfaces)."
end
