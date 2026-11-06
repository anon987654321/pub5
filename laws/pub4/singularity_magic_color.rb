# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SINGULARITY_magic_color by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 202d93a166a32f99
require_relative "master/lib/master"

Law.define(:SINGULARITY_MAGIC_COLOR) do
  source "pub4 MASTER/data/laws.yml SINGULARITY_magic_color"
  practice "A raw colour literal outside the token source."
end
