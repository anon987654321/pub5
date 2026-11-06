# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml openbsd_pf_policy by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a660e4678965b068
require_relative "master/lib/master"

Law.define(:CHECK_OPENBSD_PF_POLICY) do
  source "pub4 MASTER/checks/checks.yml openbsd_pf_policy"
  practice "Check openbsd_pf_policy holds: PF policy: default-deny, scoped ingress and SSH/bruteforce ordering intact"
end
