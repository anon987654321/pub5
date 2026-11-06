# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml KIND_ERROR_PAGE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2e2c5103a0373aad
require_relative "master/lib/master"

Law.define(:KIND_ERROR_PAGE) do
  source "pub4 MASTER/data/laws.yml KIND_ERROR_PAGE"
  practice "A static error page. A review on a finding expires in one year."
end
