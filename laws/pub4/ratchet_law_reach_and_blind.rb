# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:141 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 676e843a4961da51
require_relative "master/lib/master"

Law.define(:RATCHET_LAW_REACH_AND_BLIND) do
  source "pub4 MASTER/lib/operator/ratchets.rb:141"
  practice "Reach and fixture blindness are ratcheted; silent is observational because zero findings can mean either a healthy corpus or an applicability gap."
end
