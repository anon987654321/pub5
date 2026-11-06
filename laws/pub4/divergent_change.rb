# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1415 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1de2635286414baa
require_relative "master/law/universal"

Law.define(:DIVERGENT_CHANGE) do
  source "Refactoring - Divergent Change (Fowler)"
  ask "Is one class repeatedly changed for several unrelated causes?"
  fix "Separate the responsibilities so each has a focused reason to change."
  bad <<~'X'
    class Report; def html; end; def csv; end; def tax; end; def mail; end; end
  X
  good <<~'X'
    class Report; end; class ReportTax; end; class ReportMailer; end
  X
end
