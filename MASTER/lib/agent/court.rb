# frozen_string_literal: true

# bin/master court - a court for hard cases.
#
# Pruning removes laws that earn nothing. The harder problem is two laws
# that both earn their keep and collide - PRESERVE_FIRST against
# DO_THE_WORK_NOW, operator taste against an accessibility floor. The court
# detects the collision, lays out the evidence and the precedent on each
# side, and stops: the operator rules, and the ruling is recorded as new
# precedent. A collision becomes a reasoned decision instead of a silent
# preference. The council machinery critiques code; this adjudicates the
# constitution's hard cases, and the model never rules - it assembles the
# brief and waits.

require "yaml"
require "fileutils"
require_relative "fast_gate"

module Master
  module Agent
    module Court
      extend Base

      LEDGER = "precedents.yml"

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          case action
          when "open" then open_case(argv.drop(1))
          when "rule" then rule(argv.drop(1))
          when "cases" then cases
          else
            puts "usage: bin/master court open LAW_A --against LAW_B --question Q
       bin/master court rule CASE_ID --winner LAW --rationale R
       bin/master court cases"
            exit(64)
          end
        end

        def cases_dir
          File.join(master_root, "data", "court")
        end

        def open_case(argv)
          law_a = argv.shift
          flags = argv.each_with_index.filter_map { |a, i| %w[--against --question].include?(a) ? [a, argv[i + 1]] : nil }.to_h
          law_b = flags["--against"]
          question = flags["--question"]
          refuse("court open", "two laws are needed", "court open LAW_A --against LAW_B --question Q") if law_a.nil? || law_b.nil?
          refuse("court open", "no question given", "--question Q names the hard case in one sentence") if question.nil?

          require_relative "law_index"
          idx = LawIndex.index.fetch("laws", {})
          brief = {
            "id" => "case-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}",
            "opened_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "revision" => FastGate.head_revision,
            "status" => "awaiting-operator",
            "question" => question,
            "sides" => [law_a, law_b].map do |law|
              row = idx[law]
              {
                "law" => law,
                "statement" => row&.fetch("statement", nil),
                "severity" => row&.fetch("severity", nil),
                "bare_detector" => row&.fetch("bare_detector", false),
                "precedents_citing" => precedent_rows.select { |p| p["laws"].to_s.include?(law) }.map { |p| p["id"] },
                "taste_rows_touching" => taste_rows.select { |t| t["subject"].to_s.downcase.include?(law.to_s.downcase.split("_").first.to_s) }.map { |t| t["id"] },
              }
            end,
            "note" => "the court assembles the brief and waits; a collision of two living laws is the operator's ruling to make",
          }
          FileUtils.mkdir_p(cases_dir)
          path = File.join(cases_dir, "#{brief['id']}.yml")
          File.write(path, YAML.dump(brief))
          emit(command: "court open", case_file: "MASTER/data/court/#{brief['id']}.yml", brief:)
          0
        end

        def rule(argv)
          case_id = argv.shift
          flags = argv.each_with_index.filter_map { |a, i| %w[--winner --rationale].include?(a) ? [a, argv[i + 1]] : nil }.to_h
          winner = flags["--winner"]
          rationale = flags["--rationale"]
          refuse("court rule", "no case id given", "court rule CASE_ID --winner LAW --rationale R") if case_id.nil?
          refuse("court rule", "no winner given", "--winner names which law prevails in this collision") if winner.nil?
          refuse("court rule", "no rationale given", "a ruling without reasons is a silent preference") if rationale.nil?

          path = File.join(cases_dir, "#{case_id}.yml")
          refuse("court rule", "no case file #{case_id}", "court cases lists what is open") unless File.file?(path)

          brief = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
          refuse("court rule", "case #{case_id} is #{brief['status']}", "only an awaiting-operator case can be ruled on") unless brief["status"] == "awaiting-operator"
          refuse("court rule", "#{winner} is not a side of case #{case_id}", brief["sides"].map { |s| s["law"] }.join(" or ")) unless brief["sides"].any? { |s| s["law"] == winner }

          brief["status"] = "ruled"
          brief["ruling"] = { "winner" => winner, "rationale" => rationale,
                              "ruled_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ") }
          File.write(path, YAML.dump(brief))

          rows = precedent_rows
          new_id = "P-#{(rows.map { |p| p['id'].delete_prefix('P-').to_i }.max + 1)}"
          loser = brief["sides"].map { |s| s["law"] }.reject { |l| l == winner }
          rows << {
            "id" => new_id,
            "date" => brief["ruling"]["ruled_at"],
            "laws" => [winner],
            "question" => brief["question"],
            "ruling" => "#{winner} prevails over #{loser.first} for this collision: #{rationale}",
            "rationale" => "recorded from the operator's ruling on case #{case_id}; the losing law stands where it does not collide",
            "cites" => ["MASTER/data/court/#{case_id}.yml"],
            "overrules" => [],
            "adopted_by" => ["pub5"],
            "status" => "governing",
          }
          File.write(data_path(LEDGER), YAML.dump({ "schema" => 1, "precedents" => rows }))
          emit(command: "court rule", case: case_id, ruling: brief["ruling"], precedent_recorded: new_id)
          0
        end

        def cases
          files = Dir.glob(File.join(cases_dir, "*.yml")).sort
          emit(command: "court cases",
               cases: files.map { |f| YAML.safe_load(File.read(f), permitted_classes: [Date, Time], aliases: true).slice("id", "status", "question", "ruling") })
          0
        end

        private

        def precedent_rows
          File.file?(data_path(LEDGER)) ? load_yaml(data_path(LEDGER)).fetch("precedents", []) : []
        end

        def taste_rows
          file = data_path("taste_ledger.yml")
          File.file?(file) ? load_yaml(file).fetch("decisions", []) : []
        end
      end
    end
  end
end
