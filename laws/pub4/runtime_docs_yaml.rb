# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/meta.rb:129 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 121e9111d736cc7e
require_relative "master/law/meta"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:RUNTIME_DOCS_YAML) do
          tags %i[CONSTITUTION DOCS]
          fix "runtime-read docs must be YAML - forbid stray .md under data/"
          # A path rule: one example path cannot hold a flagged bad and a clean good.
          proved_by "test/test_scan_law_contracts.rb"
          check do |_src, path|
            rel = RuntimeDocsPaths.data_relative(path)

            next [] unless rel&.start_with?("data/") && rel.end_with?(".md")

            # data/principles/*.md is a runtime-read location by construction:
            # Ground::Constitution globs exactly that pattern and parses each file
            # into an operator-declared principle. This rule told the operator to
            # delete it, at error severity, and to move it to
            # laws.yml#operator_principles — a section that no longer exists, its
            # 47 entries having gone to law/practice.rb. A rule forbidding what a
            # live loader requires is armed and invisible for as long as the
            # directory stays empty, which it is.
            next [] if rel.match?(%r{\Adata/principles/[^/]+\.md\z})

            target = "the YAML runtime (project_context.yml, patterns.yml#skills_registry) or law/ for conduct"

            [finding(
              line: 1,
              message: "runtime docs belong in #{target} - delete #{rel}",
            )]
          end
        end
      end
    end
  end
end
