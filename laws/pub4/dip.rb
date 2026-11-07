# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DIP by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c4d6376327b4eb5c
require_relative "master/lib/master"

Law.define(:DIP) do
  source "pub4 MASTER/data/laws.yml DIP"
  practice "Dependency Inversion Principle. Depend on abstractions, not on concretions. The high-level policy of the system does not know the low-level mechanism that carries it out."
  ask "Trace high-level policy and low-level mechanisms through imports, constructor parameters, interfaces and tests. Identify whether policy code depends on concrete storage, transport, provider, framework, filesystem or runtime details. Cite dependency edges and demonstrate the change coupling caused by the dependency. Recommend inversion only when a real seam or multiple implementations justify it."
end
