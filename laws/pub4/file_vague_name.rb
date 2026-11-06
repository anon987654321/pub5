# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/naming.rb:209 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 354be62eef1c8d6a
require_relative "master/law/naming"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FILE_VAGUE_NAME) do
          tags %i[LOAD_BEARING_NAMES DOMAIN_LANGUAGE]
          fix "a filename names its subject, not a category"
          # A path rule: one example path cannot hold a flagged bad and a clean good.
          proved_by "test/test_vague_words.rb"
          check do |_src, path|
              stem = File.basename(path.to_s, ".*")
              # Rails resolves *_helper.rb, *_helpers and application_* by name, and
              # their tests mirror them, so those are framework contracts rather than
              # chosen names.
              next [] if path.to_s.match?(%r{/(?:node_modules|vendor|db/migrate)/}) ||
                         stem.match?(/_helpers?(?:_test)?\z/) || stem.start_with?("application_")

              hit = stem[/(?:\A|_)(#{Master::Ground::ParameterizedSlug::VAGUE_ALTERNATION})(?:_|\z)/, 1]
              next [] unless hit

              [finding(line: 1, message: "FILE_VAGUE_NAME: #{File.basename(path)} - " \
                                         "'#{hit}' is a category; name the subject")]
          end
        end
      end
    end
  end
end
