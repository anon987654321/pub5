# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:529 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: aa999a8e8a915cf8
require_relative "master/law/ruby"

Law.define(:EXPLICIT_HTTP_TIMEOUT) do
  source "Kleppmann, DDIA - timeouts on every outbound call"
  scope :file
  detect do |text|
    text.match?(/Net::HTTP\.(?:start|get)\b|URI\([^)]*\)\.open\b/) &&
      !text.match?(/(?:open_timeout|read_timeout|\btimeout:)/)
  end
  fix "Set open_timeout/read_timeout, or route the call through the shared HTTP boundary."
  bad  "Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }"
  good "Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.request(req) }"
end
