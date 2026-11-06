# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml rails_runtime by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3dfcf1651687551f
require_relative "master/lib/master"

Law.define(:CHECK_RAILS_RUNTIME) do
  source "pub4 MASTER/checks/checks.yml rails_runtime"
  practice "Check rails_runtime holds: pub4 check rails_runtime (rails_runtime.rb)"
end
