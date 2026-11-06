# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml dns_zones by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fd6660500c2a5267
require_relative "master/lib/master"

Law.define(:CHECK_DNS_ZONES) do
  source "pub4 MASTER/checks/checks.yml dns_zones"
  practice "Check dns_zones holds: dns_zones: repo and nsd agree (zones, nsd.conf, acme-client.conf)."
end
