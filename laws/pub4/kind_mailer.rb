# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml KIND_MAILER by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8c4b9cb72a857932
require_relative "master/lib/master"

Law.define(:KIND_MAILER) do
  source "pub4 MASTER/data/laws.yml KIND_MAILER"
  practice "A mailer template. A review on a finding expires in one year."
end
