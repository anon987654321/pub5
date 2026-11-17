# frozen_string_literal: true

# bin/master laws [--json ID] [--reindex] - the per-law dictionary.
#
# The session that wished for this fetched detector source by hand to learn
# that NO_PUTS exempts the REPL, that TIME_ZONE_UNSAFE spares .utc and .to_i,
# that PATH_PURPOSE judges MASTER only. One index answers instead: id to
# statement, severity, mode, lifecycle, languages, surfaces, path scope,
# exemptions, fixtures, proved_by. The catalogue in data/laws.yml stays the
# single source of truth; this command reads it and never restates it, and
# --reindex regenerates the committed artifact an outside agent can fetch
# without running anything.

require "yaml"

module Master
  module Agent
    module LawIndex
      extend Base

      INDEX_FILE = "laws_index.json"

      class << self
        include Base

        def run(argv)
          flags = argv.grep(/\A--/)
          argv.delete_if { |a| a.start_with?("--") }
          return reindex if flags.include?("--reindex")

          id = argv.first
          if flags.include?("--json") || !id.nil?
            id ? one(id) : all_json
          else
            all_text
          end
        end

        def index_path
          @index_path ||= data_path(INDEX_FILE)
        end

        def index
          unless File.file?(index_path)
            # A missing artifact is generated, not refused: the dictionary
            # should be readable in seconds even on a checkout that never
            # ran the rake task.
            write_index!
          end
          @index ||= JSON.parse(File.read(index_path))
        end

        def one(id)
          row = index.fetch("laws").fetch(id, nil)
          if row.nil?
            # Case-insensitive second look, then the parent chain: a child id
            # like APPLICATION_IS_UNIFORM_skipped_law carries its requirement
            # from its parent row.
            row = index.fetch("laws").values.find { |l| l["id"].casecmp?(id) }
          end
          unless row
            warn "laws: no law named #{id}; the nearest ids are listed under laws --json"
            exit(64)
          end
          emit(row)
          0
        end

        def all_json
          emit(index)
          0
        end

        def all_text
          laws = index.fetch("laws")
          puts "#{laws.size} laws, index #{index.fetch('generated_at')} at #{index.fetch('revision')}"
          laws.each_value { |row| puts format("%-44s %-8s %-10s %s", row["id"], row["severity"], row["lifecycle"], row["statement"].to_s.lines.first.to_s.strip[0, 60]) }
          0
        end

        def reindex
          write_index!
          puts "laws: index regenerated at #{index_path}"
          0
        end

        def revision
          @revision ||= begin
            head = File.join(repo_root, ".git", "HEAD")
            File.read(head).strip =~ /ref:\s*(.+)/ ? File.read(File.join(repo_root, ".git", Regexp.last_match(1))).strip : "unknown"
          rescue StandardError
            "unknown"
          end
        end

        def write_index!
          require_relative "bare_law_loader"
          require "prism"
          corpus = Master::Agent::BareCorpus.new([File.expand_path("../../law/lexical.rb", __dir__)])
          fixtures = load_yaml(File.expand_path("../../checks/data/law_fixtures.yml", __dir__))
                    .fetch("laws", {})
          statement_rows = laws_yml
          kind_rows = File.file?(data_path("law_kinds.yml")) ? load_yaml(data_path("law_kinds.yml")).fetch("kinds", []) : []

          rows = {}
          catalogue_entries.each do |id, entry|
            next unless entry.is_a?(Hash)

            statement = statement_rows[id].is_a?(Hash) ? statement_rows[id] : {}
            row = {
              "id" => id,
              "statement" => statement["statement"] ||
                             (statement["parent"] && statement_rows[statement["parent"]].is_a?(Hash) &&
                              statement_rows[statement["parent"]]["statement"]) || nil,
              "parent" => statement["parent"],
              "severity" => entry["severity"],
              "mode" => entry["mode"] || catalogue.fetch("defaults", {})["mode"] || "violation",
              "lifecycle" => entry["lifecycle"] || catalogue.fetch("defaults", {})["lifecycle"] || "active",
              "autofix" => entry["autofix"] || catalogue.fetch("defaults", {})["autofix"] || "review",
              "languages" => Array(entry["languages"]),
              "surfaces" => Array(entry["surfaces"]),
              "path_scope" => entry["path_scope"] || nil,
              "exemptions" => {
                "path_exclude" => Array(entry["path_exclude"]),
                "kinds" => kind_rows.select { |k| (k["exemptions"] || {}).key?(id) }.map { |k| k["id"] },
              },
              "fixtures" => fixtures[id] || nil,
              "proved_by" => statement["proved_by"] || entry["proved_by"],
              "definition_sources" => Array(entry["definition_sources"]),
              "bare_detector" => corpus.laws.key?(id) ? true : false,
            }
            row.delete_if { |_k, v| v.nil? }
            rows[id] = row
          end

          payload = {
            "schema" => 1,
            "generated_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "revision" => revision,
            "law_count" => rows.size,
            "laws" => rows,
          }
          File.write(index_path, JSON.pretty_generate(payload))
          @index = payload
        end
      end
    end
  end
end
