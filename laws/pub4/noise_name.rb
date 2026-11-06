# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:481 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 600402843ea6ecd3
require_relative "master/law/ruby"

Law.define(:NOISE_NAME) do
  source "Clean Code, 2nd ed. (Robert C. Martin, 2025) - class names are domain nouns, not noise words"
  detect do |line|
    line.match?(/\A\s*(?:class|module)\s+(?:[A-Z]\w*::)*(?:Manager|Utils?|Utilit(?:y|ies)|Misc|Stuff|Things?|Handlers|Foo|Bar|Baz|Te?mp)\b\s*(?:<.*)?\z/)
  end
  fix "Name it for the domain: what does it manage, hold, or do? SubscriptionBilling, not Manager."
  bad "class Manager"
  good "class SubscriptionBilling"
end
