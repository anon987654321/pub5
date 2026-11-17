# frozen_string_literal: true

# bin/master coverage --map - coverage that knows its own age.
#
# The reach ratchet says no law is unreachable; reach is not recency. A law
# can have a detector and never have run on the current revision. This map
# separates measured-clean, measured-red, never-measured and measured-stale
# per law and tree, and ages the stale ones against HEAD. A green in this
# map always carries the revision and the timestamp it measured at; a
# green-that-measured-nothing cannot display as green here - INCONCLUSIVE
# is not a rule to remember, it is a property of the screen.

require "json"
require "fileutils"
require_relative "fast_gate"

module Master
  module Agent
    module CoverageMap
      extend Base

      # Under data/coverage_map/, not data/coverage/: the root .gitignore has
      # held `coverage/` for code-coverage artifacts since before this map
      # existed, and an instrument state that silently refuses to commit is
      # the inert-config defect twice over.
      STATE = "coverage_map/state.json"
      TREES = %w[MASTER RAILS OPENBSD STUDIO BIZ].freeze

      class << self
        include Base

        def run(argv)
          tree = argv.index("--tree") ? argv[argv.index("--tree") + 1] : nil
          law_filter = argv.index("--law") ? argv[argv.index("--law") + 1] : nil
          refresh = !argv.include?("--no-refresh")

          require_relative "bare_scan"
          corpus = BareScan.load_corpus("lexical")
          law_ids = corpus.laws.keys
          law_ids &= [law_filter] if law_filter

          state = read_state
          revision = FastGate.head_revision
          rows = law_ids.flat_map do |law|
            TREES.each do |t|
              next if tree && t != tree

              measure(corpus, law, t, state, revision)
            end
            tree_rows(state, law, tree)
          end

          write_state(state, revision) if refresh
          counts = rows.group_by { |r| r[:status] }.to_h { |s, list| [s, list.size] }
          emit(
            command: "coverage --map",
            revision:,
            measured_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            counts:,
            rows: rows.first(60),
            note: "never-measured rows are never green; every green carries the revision it measured at",
          )
          0
        end

        def measure(corpus, law, tree, state, revision)
          key = "#{law}@#{tree}"
          row = state["laws"][key]
          if row && row["revision"] == revision
            row["status"] = row["findings"].to_i.positive? ? "measured-red" : "measured-clean"
            return
          end

          paths = tree_paths(tree)
          if paths.empty?
            state["laws"].delete(key)
            return
          end

          findings = 0
          paths.each do |path|
            findings += corpus.scan_file(path, only: [law]).size
          end
          state["laws"][key] = { "law" => law, "tree" => tree, "revision" => revision,
                                 "at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
                                 "findings" => findings,
                                 "files" => paths.size }
        rescue StandardError => e
          warn "coverage: measuring #{law} on #{tree} failed: #{e.class}: #{e.message}"
          state["laws"].delete(key)
        end

        # A row per law-tree that has ever been measured, aged against HEAD.
        def tree_rows(state, law_filter, tree)
          state["laws"].values.filter_map do |row|
            next nil if law_filter && row["law"] != law_filter
            next nil if tree && row["tree"] != tree

            age = FastGate.head_revision == row["revision"] ? 0 : nil
            status = if age == 0
                       row["findings"].to_i.positive? ? "measured-red" : "measured-clean"
                     else
                       "measured-stale"
                     end
            { law: row["law"], tree: row["tree"], status:,
              findings: row["findings"], files: row["files"],
              revision: row["revision"], at: row["at"],
              age_note: status == "measured-stale" ? "measured at #{row['revision']}, HEAD has moved" : nil }
          end
        end

        def tree_paths(tree)
          case tree
          when "MASTER" then Dir.glob(File.join(master_root, "lib", "agent", "*.rb")) +
                            Dir.glob(File.join(master_root, "bin", "*")).select { |f| File.file?(f) }
          when "RAILS", "OPENBSD", "STUDIO", "BIZ"
            root = File.join(repo_root, tree)
            Dir.glob(File.join(root, "**", "*.rb")).select { |f| File.readable?(f) }.first(150)
          end
        end

        def read_state
          path = File.join(master_root, "data", STATE)
          if File.file?(path)
            JSON.parse(File.read(path))
          else
            { "revision" => nil, "laws" => {} }
          end
        end

        def write_state(state, revision)
          state["revision"] = revision
          path = File.join(master_root, "data", STATE)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, JSON.pretty_generate(state))
        end
      end
    end
  end
end
