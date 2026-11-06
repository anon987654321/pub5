# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml payment_honesty by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 675aa786772b05ca
require_relative "master/lib/master"

Law.define(:CHECK_PAYMENT_HONESTY) do
  source "pub4 MASTER/checks/checks.yml payment_honesty"
  practice "Check payment_honesty holds: Payment honesty check passed."
end
