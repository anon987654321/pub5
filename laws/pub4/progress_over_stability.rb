# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:480 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 431ef6fc2b20ab10
require_relative "master/law/universal"

Law.define(:PROGRESS_OVER_STABILITY) do
  source "Progress Over Stability (Rails Doctrine, DHH)"
  ask "Is a beneficial breaking change being avoided solely to preserve compatibility when a clear upgrade path exists?"
  fix "Take the justified breaking change and provide an explicit migration path."
  bad <<~'X'
    def old_name(x); new_name(x); end
  X
  good <<~'X'
    def new_name(x); x; end
  X
end
