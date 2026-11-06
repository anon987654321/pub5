# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/meta.rb:41 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: abb84b4b06de89a8
require_relative "master/lib/master"

Law.define(:AST_OMISSION) do
  source "pub4 MASTER/law/meta.rb:41"
  practice "symbol dropped vs recent commits"
end
