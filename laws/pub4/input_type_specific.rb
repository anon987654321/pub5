# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:330 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 276215f05e8c9eeb
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:INPUT_TYPE_SPECIFIC) do
          tags %i[ACCESSIBILITY]
          fix "semantic input types for email/url/tel/date"
          bad %(<input type="text" name="email_address">\n)
          good %(<input type="email" name="email_address">\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, INPUT_GENERIC_TYPE_RE,
              message: "type=text for specialized field - use email/url/tel/date/password input type")
          end
        end
      end
    end
  end
end
