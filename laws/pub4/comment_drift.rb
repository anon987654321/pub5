# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/semantic.rb:573 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0ec998058b251eeb
require_relative "master/lib/master"

Law.define(:COMMENT_DRIFT) do
  source "pub4 MASTER/law/semantic.rb:573"
  practice "Comment claim doesn't match method body - comment is lying"
end
