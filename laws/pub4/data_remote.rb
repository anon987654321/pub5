# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:312 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bd3e591f890e8ccf
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:DATA_REMOTE) do
          tags %i[HOTWIRE]
          fix "rails-ujs data-remote - use Turbo native forms"
          bad %(<%= link_to "Slett", post_path(post), remote: true %>\n)
          good %(<%= link_to "Slett", post_path(post), data: { turbo_method: :delete } %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            scan_lines(src, /data-remote\s*=|remote:\s*true/,
              message: "data-remote/remote:true is rails-ujs - use Turbo Frame or standard form")
          end
        end
      end
    end
  end
end
