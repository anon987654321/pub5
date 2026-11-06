# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_FAMOUS_NAMES_PRESERVED by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 38c4c449c9e03ca7
require_relative "master/lib/master"

Law.define(:LINT_FAMOUS_NAMES_PRESERVED) do
  source "pub4 MASTER/data/laws.yml LINT_FAMOUS_NAMES_PRESERVED"
  practice "A law whose canonical name is well established (DRY, KISS, SOLID, POLA, YAGNI, Law of Demeter, Strunk & White, Bringhurst, Rails Doctrine, CQS, SRP, OCP, LSP, ISP, DIP) keeps that name as its id. A rename of a famous law is a rename, not a clarification."
end
