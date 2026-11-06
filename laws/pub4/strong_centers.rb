# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1051 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8c4545b9c8949e96
require_relative "master/law/universal"

Law.define(:STRONG_CENTERS) do
  source "Christopher Alexander - strong centers"
  ask "Does this artifact have one identifiable center of meaning that its parts reinforce, or is it a flat bag of unrelated pieces?"
  fix "Strengthen the central purpose and remove or relocate unrelated pieces."
  bad <<~'X'
    README with unrelated sections on finance, CSS, music, and legal notices
  X
  good <<~'X'
    README whose sections all explain how to use and govern MASTER
  X
end
