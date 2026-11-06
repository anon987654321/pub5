# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:198 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8b3354b859290272
require_relative "master/law/html"

Law.define(:NO_INLINE_SCRIPT_BLOCK) do
  source "CSP script-src / separation of concerns - assets are files"
  detect { |line| line.match?(/<script(?![^>]*\bsrc=)|<style\b(?![^>]*\bhref=)/) }
  fix "Move it to an asset file and reference it with javascript_include_tag or stylesheet_link_tag."
  bad  "<div><script>boot()</script></div>"
  good "<div></div>"
end
