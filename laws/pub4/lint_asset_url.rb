# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/asset_url_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 319c43fcf0021893
require_relative "master/lib/master"

Law.define(:LINT_ASSET_URL) do
  source "pub4 MASTER/tools/asset_url_lint.rb"
  practice "The asset url lint finds nothing above its baseline."
end
