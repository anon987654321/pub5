# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1797 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 751fbadf39674149
require_relative "master/law/universal"

Law.define(:SINGULARITY) do
  source "laws.yml SINGULARITY - one source of truth; the DRY principle of The Pragmatic Programmer"
  ask "Does this change define a fact, rule, threshold or type a second time when an existing definition already owns it, so the two copies can drift apart?"
  practice "Every fact has one owner; everything else reads it."
  fix "Find the existing owner and read from it. If none exists, create one and move every copy onto it in the same change."
  bad "Add a second Law type whose members mirror the one in the kernel, each carrying its own copy of the same threshold."
  good "Reuse the kernel's Law type and read the threshold from the single file that owns it."
end
