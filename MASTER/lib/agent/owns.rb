# frozen_string_literal: true

# bin/master owns PATH - who owns this path.
#
# The cross-tree coupling is real and documented; the session that wished for
# this rebuilt it with greps. One query composes what already owns a path:
# the PATH_OWNERSHIP entry, the laws that reach it (from the generated law
# index), the test files that prove it, and the callers that name it.
# ReferenceGraph and CodeIndex keep the heavy graph; when their stores are
# absent this answers from the filesystem and says so, rather than guessing.

require "yaml"

module Master
  module Agent
    module Owns
      extend Base

      class << self
        include Base

        def run(argv)
          path = argv.first
          refuse("owns", "no PATH given", "a path relative to the repo root or to MASTER/, e.g. MASTER/lib/agent or data/gaps.yml") if path.nil?

          normalized = normalize(path)
          emit(
            command: "owns",
            path: path,
            normalized: normalized,
            ownership: ownership_entry(normalized),
            laws: owning_laws(normalized),
            tests: owning_tests(normalized),
            callers: callers(normalized),
            reference_graph: not_run("reference_graph", "the graph store is built by the full runtime; this answer came from the filesystem only"),
          )
          0
        end

        def normalize(path)
          path = path.delete_prefix("/")
          path = File.join("MASTER", path) unless path.match?(%r{\A(?:MASTER|RAILS|OPENBSD|STUDIO|BIZ)/}) || path.start_with?("bin/", "scripts/", "data/")
          path
        end

        def ownership_map
          @ownership_map ||= load_yaml(File.join(master_root, "PATH_OWNERSHIP.yml")).fetch("ownership", {})
        end

        def ownership_entry(normalized)
          hits = []
          ownership_map.each do |key, entry|
            clean = key.delete_prefix("../")
            if key.end_with?("/")
              hits << { key:, purpose: entry["purpose"], risk: entry["risk"], check: entry["check"], match: "directory" } if normalized.start_with?(clean)
            elsif normalized == clean || normalized.end_with?("/#{clean}")
              hits << { key:, purpose: entry["purpose"], risk: entry["risk"], check: entry["check"], match: "exact" }
            end
          end
          # The deepest key wins; a directory owner is the fallback, not the answer.
          hits.sort_by { |h| [h[:match] == "exact" ? 1 : 0, h[:key].length] }.last || "no PATH_OWNERSHIP entry; adding one is the fix, not a silent default"
        end

        def owning_laws(normalized)
          require_relative "law_index"
          idx = LawIndex.index
          laws = []
          idx.fetch("laws", {}).each_value do |row|
            sources = Array(row["definition_sources"])
            excludes = Array(row.dig("exemptions", "path_exclude"))
            names_path = sources.any? { |s| normalized.include?(File.basename(s.to_s, ".rb")) } ||
                         excludes.any? { |pattern| File.basename(normalized).match?(Regexp.new(pattern)) rescue false }
            laws << { id: row["id"], severity: row["severity"], reach: excludes.any? ? "exempts" : "names" } if names_path
          end
          laws.first(12)
        end

        def owning_tests(normalized)
          stem = File.basename(normalized, ".*")
          Dir.glob(File.join(master_root, "test", "**", "*#{stem}*")).map { |t| t.delete_prefix("#{repo_root}/") }.first(8)
        end

        def callers(normalized)
          needle = File.basename(normalized, File.extname(normalized))
          needle = Regexp.escape(needle)
          roots = %w[bin lib tools checks law].map { |d| File.join(master_root, d) }
          found = []
          roots.each do |root|
            Dir.glob(File.join(root, "**", "*.{rb,sh,zsh,yml}")).each do |file|
              next if file.include?("/agent/")

              body = File.read(file) rescue next
              found << file.delete_prefix("#{repo_root}/") if body.match?(/#{needle}/)
            end
          end
          found.first(10)
        end
      end
    end
  end
end
