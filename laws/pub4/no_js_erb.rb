# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:299 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a3df97f6decc3306
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_JS_ERB) do
          tags %i[HOTWIRE]
          fix "RJS and format.js - migrate to Turbo Streams"
          bad %(<%= render "posts/create.js.erb" %>\n)
          good %(<%= render "posts/create.turbo_stream.erb" %>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            findings = scan_lines(src, /format\.js\s*\{/, message: "format.js - use format.turbo_stream")
            findings += scan_lines(src, /\.js\.erb\b/, message: ".js.erb - replace with turbo_stream templates")
            findings
          end
        end
      end
    end
  end
end
