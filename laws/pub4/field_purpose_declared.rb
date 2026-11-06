# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:479 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e9d8f2040c5bea93
require_relative "master/law/html"

module Law
  ::Law.define(:FIELD_PURPOSE_DECLARED) do
    source "WCAG 1.3.5 Identify Input Purpose, AA; Wroblewski, Web Form Design (2008); Baymard checkout research"
    tags %i[ACCESSIBILITY]
    path M::TEMPLATES
    fix "Give each personal-data field its autofill token (autocomplete: \"postal-code\") and inputmode for digits."
    bad "<%= f.text_field :postnummer %>\n"
    good "<%= f.text_field :postnummer, autocomplete: \"postal-code\", inputmode: \"numeric\" %>\n"
    check do |src, _path|
      M.statements(src, M::FIELD).filter_map { |text, line| (message = M.purpose(text)) && finding(line:, message:) }
    end
  end
end
