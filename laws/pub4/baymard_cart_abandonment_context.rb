# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BAYMARD_CART_ABANDONMENT_CONTEXT by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 71fafb09d4e85efd
require_relative "master/lib/master"

Law.define(:BAYMARD_CART_ABANDONMENT_CONTEXT) do
  source "pub4 MASTER/data/laws.yml BAYMARD_CART_ABANDONMENT_CONTEXT"
  practice "Cart abandonment is an outcome, not a diagnosis. Distinguish browsing and unready intent from avoidable friction; never treat an aggregate abandonment rate alone as proof of a design defect or as permission to coerce a purchase."
end
