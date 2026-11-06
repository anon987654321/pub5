# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:825 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a766de0c15c3feb4
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:HELPER_VIEW_ONLY) do
          tags %i[RAILS]
          fix "helpers format for views only"
          example_path "/repo/app/helpers/example_helper.rb"
          bad "def recent_posts\n  Post.where(published: true)\nend\n"
          good "def title_for(post)\n  post.title.upcase\nend\n"
          check do |src, path|
            next [] unless path.to_s.include?("/helpers/")

            next [] unless src.match?(/\b(?:ActiveRecord|ApplicationRecord|\.where\(|\.find\()/)
            [finding(line: 1, message: "AR access in helper - helpers format only; queries belong in models")]
          end
        end
      end
    end
  end
end
