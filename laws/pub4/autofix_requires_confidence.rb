# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1788 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bac90dbe4a8a07c3
require_relative "master/law/universal"

Law.define(:AUTOFIX_REQUIRES_CONFIDENCE) do
  source "MASTER autofix safety policy"
  ask "Is this finding sufficiently deterministic that an automatic edit can be applied without guessing at user intent or hidden semantics?"
  practice "LLM-generated text is not evidence that an automatic transformation is safe."
  fix "Downgrade to review-only or add deterministic evidence and preservation tests before automatic repair."
  bad "A semantic smell triggers an automatic rewrite because the model produced plausible code."
  good "Only a deterministic, fixture-proven transformation is eligible for automatic repair."
end
