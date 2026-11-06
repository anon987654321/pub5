# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1171 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d18279266141cd20
require_relative "master/law/universal"

Law.define(:DOMAIN_LANGUAGE) do
  source "Domain-Driven Design - Ubiquitous Language (Eric Evans)"
  ask "Does this code or document use generic terms where the domain has a clearer established term?"
  fix "Use the vocabulary the domain actually uses."
  bad <<~'X'
    data = invoice.total
  X
  good <<~'X'
    invoice_total = invoice.total
  X
end
