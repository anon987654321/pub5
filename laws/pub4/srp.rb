# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1257 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 581d1e88ac50222b
require_relative "master/law/universal"

Law.define(:SRP) do
  source "SOLID - Single Responsibility Principle (Robert C. Martin)"
  ask "Does this class or module have more than one reason to change?"
  fix "Give each responsibility a distinct owner and boundary."
  bad <<~'X'
    class Invoice; def calculate; end; def render; end; def email; end; end
  X
  good <<~'X'
    class Invoice; def calculate; end; end; class InvoiceRenderer; end; class InvoiceMailer; end
  X
end
