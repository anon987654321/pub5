# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_img_alt by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8c50ca821a3b569d
require_relative "master/lib/master"

Law.define(:REACH_IMG_ALT) do
  source "pub4 MASTER/data/laws.yml REACH_img_alt"
  practice "An image with no alt text, not marked decorative."
end
