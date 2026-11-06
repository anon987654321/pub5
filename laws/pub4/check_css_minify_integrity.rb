# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml css_minify_integrity by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ede7beb3be94867b
require_relative "master/lib/master"

Law.define(:CHECK_CSS_MINIFY_INTEGRITY) do
  source "pub4 MASTER/checks/checks.yml css_minify_integrity"
  practice "Check css_minify_integrity holds: css_minify_integrity: ok"
end
