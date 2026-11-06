# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml rendered_suite by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 987af1c9d9fd2eb5
require_relative "master/lib/master"

Law.define(:CHECK_RENDERED_SUITE) do
  source "pub4 MASTER/checks/checks.yml rendered_suite"
  practice "Check rendered_suite holds: ok: rendered browser suite clean"
end
