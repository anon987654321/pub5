# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1015 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 55fef03d8343d158
require_relative "master/law/universal"

Law.define(:PARSE_DONT_VALIDATE) do
  source "Alexis King - parse, don't validate"
  ask "Is the same input re-checked at many call sites instead of being parsed once into a value carrying the guarantee?"
  fix "Parse once at the boundary and pass the proven value inward."
  bad <<~'X'
    def send(url); raise unless url.start_with?("https:"); fetch(url); end
  X
  good <<~'X'
    url = HttpsUrl.parse(raw); fetch(url)
  X
end
