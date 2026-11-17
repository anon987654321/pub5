# frozen_string_literal: true

# bin/master status --agent - one read across the ledgers.
#
# TODO.md, operator_seams.yml, gaps.yml, convergence.yml and proposals.yml
# each hold a part of what is open. An outside agent read all seven files to
# learn what was open; the one-backlog rule stays, and so does every ledger's
# own authority - this view unions them and points at the owning file and
# line, it does not become a second backlog. Rows land in four buckets:
# actionable-now (an agent can start), needs-proof (blocked on a measurement),
# needs-operator (blocked on a person, a device or a credential) and refused
# (checked and wrong; the reason is kept so it is not re-proposed).

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
          rows = todo_rows + seams_rows + gaps_rows + proposals_rows + convergence_rows
          buckets = %w[actionable-now needs-proof needs-operator refused].to_h { |b| [b, []] }
          rows.each { |row| buckets[row[:bucket]] << row }

          {
            command: "status --agent",
            generated_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            counts: buckets.to_h { |b, list| [b, list.size] },
            buckets: buckets.to_h do |bucket, list|
              [bucket, list.first(30).map { |r| r.sort_by { |k, _v| k.to_s }.to_h }]
            end,
            truncated: buckets.values.map(&:size) != buckets.values.map { |l| l.first(30).size },
            sources: ["TODO.md", "MASTER/data/operator_seams.yml", "MASTER/data/gaps.yml",
                      "MASTER/data/proposals.yml", "MASTER/convergence.yml"],
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

        def bucket_for(title)
          title_down = title.downcase
          return "refused" if title_down.match?(/\brefused\b|\bnever\b/i)

          return "needs-operator" if OPERATOR_WORDS.any? { |w| title_down.include?(w) }
          return "needs-proof" if title_down.match?(/\bproof\b|\bNOT_RUN\b|\bevidence\b|\bverify\b|\brendered\b/i)

          "actionable-now"
        end

        def todo_rows
          path = File.join(repo_root, "TODO.md")
          return [] unless File.file?(path)

          rows = []
          section = nil
          File.readlines(path).each_with_index do |line, i|
            section = line.strip.delete_prefix("#").strip if line.start_with?("#")
            next unless line.match?(/^\s*- \[ \]/)

            title = line.sub(/^\s*- \[ \]\s*/, "").strip
            rows << { source: "TODO.md", line: i + 1, title: title[0, 110],
                      tree: section.to_s.split(" ")[0], why: nil,
                      bucket: bucket_for(title), id: "todo-#{i + 1}" }
          end
          rows
        end

        def seams_rows
          path = data_path("operator_seams.yml")
          return [] unless File.file?(path)

          seams = load_yaml(path).fetch("seams", [])
          seams.map do |seam|
            { source: "MASTER/data/operator_seams.yml", line: seam[:__line] || 0, id: seam["id"],
              tree: seam["tree"], title: seam["id"], why: "needs: #{seam['needs']}",
              bucket: "needs-operator" }
          end
        end

        def gaps_rows
          path = data_path("gaps.yml")
          return [] unless File.file?(path)

          load_yaml(path).fetch("gaps", []).filter_map do |gap|
            next nil if %w[satisfied rejected].include?(gap["status"])

            bucket = gap["status"] == "picked" ? "actionable-now" : "needs-proof"
            { source: "MASTER/data/gaps.yml", line: 0, id: gap["id"], title: gap["name"],
              tree: gap["app"], why: "status #{gap['status']}: absence has no diff; ideation first",
              bucket: }
          end
        end

        def proposals_rows
          path = data_path("proposals.yml")
          return [] unless File.file?(path)

          load_yaml(path).fetch("proposals", []).filter_map do |prop|
            next nil if prop["state"] == "landed"

            bucket = prop["state"] == "refuted" ? "refused" : "actionable-now"
            { source: "MASTER/data/proposals.yml", line: 0, id: prop["id"], tree: prop["tree"],
              title: prop["claim"].to_s.lines.first.to_s.strip[0, 110],
              why: prop["state"] == "refuted" ? prop["reason"].to_s.lines.first.to_s.strip[0, 90] : nil,
              bucket: }
          end
        end

        def convergence_rows
          path = File.join(master_root, "convergence.yml")
          return [] unless File.file?(path)

          data = load_yaml(path)
          streams = data.is_a?(Hash) ? (data["workstreams"] || data["streams"] || []) : []
          streams.filter_map do |ws|
            next nil unless ws.is_a?(Hash)

            state = ws["status"] || ws["state"] || "open"
            bucket = %w[done landed complete].include?(state) ? nil :
                       (%w[blocked operator].include?(state) ? "needs-operator" : "needs-proof")
            next nil unless bucket

            { source: "MASTER/convergence.yml", line: 0, id: ws["id"] || ws["name"],
              title: (ws["name"] || ws["goal"]).to_s.lines.first.to_s.strip[0, 110],
              why: "status #{state}", bucket: }
          end
        end
      end
    end
  end
end
