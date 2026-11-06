# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml pwa_installable by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a3afa917cea23ef8
require_relative "master/lib/master"

Law.define(:CHECK_PWA_INSTALLABLE) do
  source "pub4 MASTER/checks/checks.yml pwa_installable"
  practice "Check pwa_installable holds: ok: three manifests installable, icons resolve, brgen follows its host"
end
