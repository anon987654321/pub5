# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1641 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2146375231e7aac0
require_relative "master/law/universal"

Law.define(:SURFACE_AREA) do
  source "API design - minimize public surface area"
  ask "Is the public interface larger than necessary, exposing entry points or exceptions callers do not need?"
  fix "Reduce the public contract to the smallest useful surface and keep internals private."
  bad <<~'X'
    class Client; def fetch; end; def retry; end; def parse; end; def raw_response; end; end
  X
  good <<~'X'
    class Client; def fetch; end; end
  X
end
