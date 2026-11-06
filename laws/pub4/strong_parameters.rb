# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:648 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3f18c99f8af95705
require_relative "master/law/ruby"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:STRONG_PARAMETERS) do
          tags %i[SECURITY]
          fix "mass assignment goes through explicitly permitted attributes"
          bad "Post.create(params[:post])\n"
          good "Post.create(params.require(:post).permit(:title))\n"
          check do |src, path|
            next [] unless path.include?("/app/")

            blanket = scan_lines(src, /\.permit!/,
              message: "permit! whitelists every attribute - name the permitted attributes instead")
            raw = scan_lines(src,
              /\.(?:new|create!?|update!?|update_attributes!?|assign_attributes)\(\s*params\[/,
              message: "raw params[] reaches mass assignment - route it through require(...).permit(...)")
            blanket + raw
          end
        end
      end
    end
  end
end
