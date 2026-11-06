# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/naming.rb:9 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 786f0e6a7c641366
require_relative "master/law/naming"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PARAMETERIZED_SLUG) do
          tags %i[FLAT_HIERARCHY DRY]
          fix "path is dense Rails-parameterize slug - Strunk-clean snake_case"
          # A path rule: one example path cannot hold a flagged bad and a clean good.
          proved_by "test/test_parameterized_slug.rb"
          check do |_src, path|
            rel = path.to_s
            # A migration's filename is its schema_migrations key, and Rails finds
            # application_* by name. Neither can be renamed on naming-density
            # grounds, and 58 of brgen's 71 findings were migrations.
            next [] if rel.match?(%r{/(test|spec|node_modules|db/migrate)/|/application_\w+\.rb\z})

            Master::Ground::ParameterizedSlug.path_issues(rel).map do |issue|
              target = issue.to == issue.from ? issue.to : "#{File.dirname(rel)}/#{issue.to}.rb".gsub(%r{\./}, "")
              message = case issue.action
                        when "merge" then "Flat Hierarchy - #{issue.reason} (#{target})"
                        else "Flat Hierarchy - #{issue.reason}#{" -> #{target}" if issue.to != issue.from}"
                        end
              finding(line: 1, message:)
            end
          end
        end
      end
    end
  end
end
