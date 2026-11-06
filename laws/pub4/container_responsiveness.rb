# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:152 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 49f34f005799cd96
require_relative "master/law/css"

Law.define(:CONTAINER_RESPONSIVENESS) do
  source "CSS Container Queries - web.dev Learn CSS"
  ask "Does a reusable component respond to the viewport even though its actual constraint is the size of its containing component?"
  fix "Use a named or nearest container query when the component's behavior depends on container size."
  bad "@media (max-width: 700px) { .card { ... } }"
  good "@container (max-width: 30rem) { .card { ... } }"
end
