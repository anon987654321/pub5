# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:411 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: aad1bc36f50a5be6
require_relative "master/lib/master"

Law.define(:RATCHET_COMMAND) do
  source "pub4 MASTER/lib/operator/ratchets.rb:411"
  practice "Every name a person or a model can type, across the three surfaces that accept one: the CLI's closed table, the words the router accepts as meaning the pipeline, and bin/operator's subcommands."
end
