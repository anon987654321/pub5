# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ISP by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: acaeec2457933573
require_relative "master/lib/master"

Law.define(:ISP) do
  source "pub4 MASTER/data/laws.yml ISP"
  practice "Interface Segregation Principle. A client depends only on the methods it uses. An interface that forces a client to depend on methods it never calls has bound the client to changes it does not care about."
  ask "For each interface, enumerate clients and methods each client uses. Identify clients forced to depend on methods they never call, unused stubs, avoidable mocks, or implementation methods raising unsupported. Recommend the smallest client-facing interfaces and cite call sites; do not fragment interfaces without demonstrated clients."
end
