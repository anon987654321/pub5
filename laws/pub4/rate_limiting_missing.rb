# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:208 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b951fcabc369a4f9
require_relative "master/law/ruby"

Law.define(:RATE_LIMITING_MISSING) do
  path "/app/controllers/"
  source "OWASP API Security - rate limiting"
  scope :file
  # A controller that includes the shared actions module inherits its limits,
  # and the module is scanned on its own.
  absent /rate_limit|throttle|include\s+(?:\w+::)*\w*(?:Sessions|Passwords|Registrations)Actions\b/
  # An action, not a word. Reading the file for "password" anywhere flagged
  # the authentication concern for calling reset_session, SSO provisioning for
  # generating a random password, and dating's base controller for a predicate
  # named vipps_login_available? — none of which is an endpoint. What takes a
  # credential is a controller or actions module named for sessions, passwords
  # or registrations, or an action whose own name says login, signup or reset.
  detect do |text|
    text.match?(/^\s*(?:class|module)\s+(?:\w+::)*\w*(?:Sessions|Passwords|Registrations|Signups?)(?:Controller|Actions)\b/) ||
      text.match?(/^\s*def\s+\w*(?:login|signup|sign_up|password|reset)\w*(?![\w?!])/)
  end
  fix "Add rate_limit/throttle to sensitive actions."
  bad <<~X
    def login
    end
  X
  good <<~X
    rate_limit to: 5, within: 1.minute
    def login
    end
    def vipps_login_available?
    end
  X
end
