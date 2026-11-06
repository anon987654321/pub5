# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/chrome_i18n_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: aa2f9d09e17bb6ed
require_relative "master/lib/master"

Law.define(:LINT_CHROME_I18N) do
  source "pub4 MASTER/tools/chrome_i18n_lint.rb"
  practice "21 -> 9 (2026-08-25): the i18n pass on the engines."
end
