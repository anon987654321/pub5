# frozen_string_literal: true

# bin/master status --agent - one read across the owning registries.
#
# Each owner keeps its own IDs, evidence and lifecycle: operator seams,
# product gaps, convergence workstreams, UX acceptance contracts, RAILS
# refinements and the refutation ledger. This view is a projection only; it
# never writes or becomes another backlog.
#
# Rows land in four buckets: actionable-now (picked or explicitly open work),
# needs-proof (acceptance evidence still required), needs-operator (a person,
# device, credential or external environment), and refused (a proposal checked
# and rejected, retained with its reason).

require "yaml"

module Master
  module Agent
    module StatusView
      extend Base

      OPERATOR_WORDS = %w[operator console vm23 registrar device credential browser paid password
                          rights photographs ears person's manual decision].freeze

      class << self
        include Base

        def run(argv)
          flags = argv.select { |a| a.start_with?("--") }
          emit(flags.include?("--text") ? text_view : view)
          0
        end

        def view
          rows = seams_rows + gaps_rows + proposals_rows + convergence_rows + ux_rows + rails_refinement_rows
          rows = deduplicate(rows)
          buckets = %w[actionable-now needs-proof needs-operator refused].to_h { |b| [b, []] }
          rows.each { |row| buckets.fetch(row[:bucket]) << row }

          {
            command: "status --agent",
            generated_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            counts: buckets.to_h { |b, list| [b, list.size] },
            buckets: buckets.to_h do |bucket, list|
              [bucket, list.first(30).map { |r| r.sort_by { |k, _v| k.to_s }.to_h }]
            end,
            truncated: buckets.values.map(&:size) != buckets.values.map { |l| l.first(30).size },
            sources: [
              "MASTER/data/operator_seams.yml",
              "MASTER/data/gaps.yml",
              "MASTER/data/proposals.yml",
              "MASTER/convergence.yml",
              "MASTER/data/law/ux_refinements.yml",
              "RAILS/refinements.yml",
            ],
          }
        end

        def text_view
          v = view
          lines = v[:buckets].flat_map do |bucket, list|
            ["", "== #{bucket} (#{v[:counts][bucket]})"] +
              list.map { |r| "#{r[:source]}:#{r[:line]} #{r[:title]}#{r[:why] ? " - #{r[:why]}" : ''}" }
          end
          { counts: v[:counts], lines: lines.compact }
        end

        def seams_rows
          path = data_path("operator_seams.yml")
          return [] unless File.file?(path)

          load_yaml(path).fetch("seams", []).map do |seam|
            {
              source: "MASTER/data/operator_seams.yml",
              line: seam[:__line] || 0,
              id: seam["id"],
              tree: seam["tree"],
              title: seam["id"],
              why: "needs: #{seam['needs']}; #{seam['evidence']}".strip[0, 180],
              bucket: "needs-operator",
            }
          end
        end

        def gaps_rows
          path = data_path("gaps.yml")
          return [] unless File.file?(path)

          data = load_yaml(path)
          workstream_ids = convergence_ids
          data.fetch("gaps", []).filter_map do |gap|
            next if %w[satisfied rejected].include?(gap["status"])
            # The workstream is the implementation/evidence owner for a picked gap.
            # Showing both creates two tickets for the same work.
            next if workstream_ids.include?(gap["workstream"].to_s) && !gap["workstream"].to_s.empty?

            bucket = case gap["status"]
                     when "picked" then "actionable-now"
                     when "blocked" then "needs-operator"
                     else "actionable-now"
                     end
            {
              source: "MASTER/data/gaps.yml",
              line: 0,
              id: gap["id"],
              tree: gap["app"],
              title: gap["name"],
              why: [gap["status"], gap["note"]].compact.join(": ")[0, 180],
              bucket:,
            }
          end
        end

        def proposals_rows
          path = data_path("proposals.yml")
          return [] unless File.file?(path)

          load_yaml(path).fetch("proposals", []).filter_map do |proposal|
            next if proposal["state"] == "landed"

            refused = proposal["state"] == "refuted"
            {
              source: "MASTER/data/proposals.yml",
              line: 0,
              id: proposal["id"],
              tree: proposal["tree"],
              title: proposal["claim"].to_s.lines.first.to_s.strip[0, 110],
              why: refused ? proposal["reason"].to_s.lines.first.to_s.strip[0, 90] : nil,
              bucket: refused ? "refused" : "actionable-now",
            }
          end
        end

        def convergence_rows
          path = File.join(master_root, "convergence.yml")
          return [] unless File.file?(path)

          data = load_yaml(path)
          streams = data.is_a?(Hash) ? (data["workstreams"] || data["streams"] || []) : []
          streams.filter_map do |stream|
            next nil unless stream.is_a?(Hash)

            state = stream["state"] || stream["status"] || "missing"
            bucket = case state
                     when "landed", "done", "complete" then nil
                     when "rejected" then "refused"
                     when "operator", "evidence" then "needs-operator"
                     else "needs-proof"
                     end
            next nil unless bucket

            {
              source: "MASTER/convergence.yml",
              line: 0,
              id: stream["id"] || stream["name"],
              title: (stream["title"] || stream["name"] || stream["goal"]).to_s.lines.first.to_s.strip[0, 110],
              why: "state #{state}; proof: #{stream['proof']}".slice(0, 180),
              bucket:,
            }
          end
        end

        def ux_rows
          path = data_path("law/ux_refinements.yml")
          return [] unless File.file?(path)

          load_yaml(path).fetch("refinements", []).filter_map do |row|
            state = row["state"].to_s
            next if %w[landed complete satisfied rejected].include?(state)

            {
              source: "MASTER/data/law/ux_refinements.yml",
              line: 0,
              id: row["id"],
              tree: Array(row["owner_trees"]).join(","),
              title: "#{row['id']} #{row['title']}",
              why: "acceptance required: #{Array(row['proof']).join(', ')}",
              bucket: "needs-proof",
            }
          end
        end

        def rails_refinement_rows
          path = File.join(repo_root, "RAILS", "refinements.yml")
          return [] unless File.file?(path)

          load_yaml(path).fetch("items", []).filter_map do |row|
            next if %w[landed complete satisfied rejected].include?(row["status"].to_s)

            {
              source: "RAILS/refinements.yml",
              line: 0,
              id: row["id"],
              tree: "RAILS",
              title: "#{row['id']} #{row['item']}".slice(0, 110),
              why: "status #{row['status']}; source: #{row['path']}",
              bucket: "needs-proof",
            }
          end
        end

        def convergence_ids
          path = File.join(master_root, "convergence.yml")
          return [] unless File.file?(path)

          data = load_yaml(path)
          Array(data["workstreams"] || data["streams"]).filter_map { |row| row["id"].to_s }
        end

        # Owner IDs are stable. The first source in the order above owns the
        # projection; duplicate secondary references do not become extra work.
        def deduplicate(rows)
          seen = {}
          rows.each_with_object([]) do |row, result|
            key = row[:id].to_s
            next if key.empty? || seen[key]

            seen[key] = true
            result << row
          end
        end
      end
    end
  end
end
