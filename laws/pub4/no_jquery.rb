# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:226 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 80d382179b875be5
require_relative "master/law/html"

Law.define(:NO_JQUERY) do
  source "RAILS/__shared frontend convention"
  detect { |line| line.match?(/jQuery\(|\$\((?=\s*["\x27#.])/) }
  fix "Replace the selector call with a Stimulus target or querySelector."
  bad  "$('#menu').show()"
  good "document.querySelector('#menu').hidden = false"
end
