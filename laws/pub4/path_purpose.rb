# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/meta.rb:555 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: afe646396db3ed38
require_relative "master/law/meta"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PATH_PURPOSE) do
          detector PathPurposeLaw
          tags %i[ONE_SOURCE COLLAPSE_BEFORE_ADDING]
          fix "every directory declares its purpose in PATH_OWNERSHIP.yml"
          proved_by "test/test_path_purpose_law.rb"
        end
      end
    end
  end
end
