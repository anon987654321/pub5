# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:592 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 42e992c426b76cb0
require_relative "master/lib/master"

Law.define(:RATCHET_FILE_LENGTH) do
  source "pub4 MASTER/lib/operator/ratchets.rb:592"
  practice "POINTED AT, NOT RE-MEASURED — and the first version of this method is why."
end
