# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:242 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 89bd8c54eebbf03f
require_relative "master/law/universal"

Law.define(:SECRET_PROXIMITY) do
  source "OWASP - no hardcoded secrets/credentials"
  # The value must be a CLOSED quoted literal, and the identifier must not
  # itself sit inside a string. `[^'"]{8,}` had no reason to stay inside a
  # quote, so it matched the source BETWEEN two literals — the "secret" it
  # reported in auth_tier.rb was the code `token=") || p == `. At :error
  # severity, which also gated that file out of the semantic pass.
  #
  # An interpolated value is assembled at run time and cannot BE a literal
  # secret. `token = "#{vertical}_#{key}"` builds a design-token name, and the
  # literal is the whole point of the rule.
  detect do |line|
    # Shell expansion counts too: `export HUGGINGFACE_HUB_TOKEN="${HF_TOKEN}"`
    # forwards a value the environment already holds, which is the fix this rule
    # asks for rather than the defect it names.
    next false if line.match?(/=\s*"[^"\n]*(?:#\{|\$\{|\$\w)/)

    line.match?(/(?<!['"])(password|secret|token|api_key|private_key)\s*=\s*(?:"[^"\n]{8,}"|'[^'\n]{8,}')/i)
  end
  fix "Move secret to environment variable or secrets manager."
  bad "api_key = 'sk_live_abcdef123456'"
  good "api_key = ENV.fetch('API_KEY')"
end
