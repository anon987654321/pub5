# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:160 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a6a2767981744c70
require_relative "master/law/css"

Law.define(:MODERN_FORMS) do
  source "CSS field-sizing - Baseline 2026"
  ask "Does a form control use brittle fixed sizing where its content, label, validation state, or user input should determine its size?"
  fix "Prefer intrinsic form sizing and field-sizing when it improves the control without harming predictability."
  bad "textarea { height: 96px; }"
  good "textarea { field-sizing: content; }"
end
