# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:206 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 529aed3be7a64dd0
require_relative "master/law/html"

Law.define(:NO_INLINE_STYLES) do
  source "CSP / separation of concerns - no inline styles"
  # A style attribute carrying only custom properties is a data channel to
  # the stylesheet — style="--swatch: teal" hands a value to a rule that
  # lives in CSS (color: var(--swatch)), which is the separation this law
  # wants. A real property inline still fires.
  #
  # The marker convention the other laws honour applies here too: a line that
  # says `scan: intentional` carries its reason beside it — the mailer
  # preheader (mail clients load no bundle), AdSense's required inline
  # display on <ins>, a honeypot no stylesheet may reveal, and helpers whose
  # whole emission is one custom property the detector cannot see through
  # ERB. The marker is read on the line, so an intentional style cannot
  # silently cover its neighbours.
  detect { |line| (value = line[/\bstyle="([^"]*)"/, 1]) && !value.match?(/\A\s*(?:--[\w-]+:\s*[^;"]*;?\s*)*\z/) && !line.match?(/scan:\s*intentional\b/) }
  fix "Extract to CSS class; pass dynamic values as custom properties."
  bad  "<p style=\"color:red\">"
  good "<p class=\"warn\" style=\"--share: 40%\">"
end
