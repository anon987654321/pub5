# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml affiliate_honesty by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5add04bc44d83647
require_relative "master/lib/master"

Law.define(:CHECK_AFFILIATE_HONESTY) do
  source "pub4 MASTER/checks/checks.yml affiliate_honesty"
  practice "Check affiliate_honesty holds: Affiliate honesty check passed."
end
