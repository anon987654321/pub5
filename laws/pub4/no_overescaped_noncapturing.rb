# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/fix_hygiene.rb:21 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 619f0770fd24dcb0
require_relative "master/law/fix_hygiene"

Law.define(:NO_OVERESCAPED_NONCAPTURING) do
  source "MASTER post-incident /fix hardening - extract-then-match regex integrity"
  detect do |line|
    code = line.gsub(/(['"]).*?\1/, "")
    code.include?("\\\\(?:")
  end
  fix "Match the extracted regex body with regex syntax appropriate to the body; do not add source-level escaping twice."
  bad 'body.scan(/phantom:\\\\(?:detected|halt|recovery)/)'
  good "body.scan(/phantom:(detected|halt|recovery)/)"
end
