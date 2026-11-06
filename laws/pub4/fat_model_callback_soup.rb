# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:748 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5bde432e00bc85a7
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FAT_MODEL_CALLBACK_SOUP) do
          tags %i[RAILS ARCHITECTURE]
          fix "limit model callback piles"
          example_path "/repo/app/models/example.rb"
          bad %w[before_validation before_save after_save after_create after_update after_commit]
                 .map { |cb| "  #{cb} :touch_feed\n" }.join
          good "  before_validation :normalise_slug\n  after_commit :broadcast\n"
          check do |src, path|
            next [] unless path.to_s.include?("/models/")

            count = src.scan(/^\s*(?:before|after|around)_(?:validation|save|create|update|destroy|commit)/).size
            next [] if count <= 5
            [finding(line: 1, message: "#{count} AR callbacks - prefer services/events over callback soup")]
          end
        end
      end
    end
  end
end
