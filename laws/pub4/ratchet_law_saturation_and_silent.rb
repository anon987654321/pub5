# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:153 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7aa7e284b8c81b3d
require_relative "master/lib/master"

Law.define(:RATCHET_LAW_SATURATION_AND_SILENT) do
  source "pub4 MASTER/lib/operator/ratchets.rb:153"
  practice "The law saturation and silent ratchet never rises above its ceiling and never sits below it unlowered."
end
