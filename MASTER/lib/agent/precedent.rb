# frozen_string_literal: true

# bin/master precedent - engineering law that accumulates the way case law
# does.
#
# A law refined in one place propagates with its evidence and its parentage;
# a tree that disagrees dissents with reasons; the corpus records which
# jurisdictions adopted which ruling. The rows live in data/precedents.yml,
# seeded with rulings the tree already made and recorded. This command reads
# them, cites them, records overrulings and adoptions - it never invents a
# ruling nobody made.

require "yaml"
require_relative "fast_gate"

module Master
  module Agent
    module Precedent
      extend Base

      LEDGER = "precedents.yml"

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          case action
          when "list" then list
          when "cite" then cite(argv.drop(1))
          when "overrule" then overrule(argv.drop(1))
          when "adopt" then adopt(argv.drop(1))
          else
            puts "usage: bin/master precedent list [--law ID]
       bin/master precedent cite ID
       bin/master precedent overrule ID --reason R [--evidence FILE]
       bin/master precedent adopt ID --tree TREE"
            exit(64)
          end
        end

        def ledger
          @ledger ||= load_yaml(data_path(LEDGER)).fetch("precedents", [])
        end

        def save(rows)
          File.write(data_path(LEDGER), YAML.dump({ "schema" => 1, "precedents" => rows }))
        end

        def list(argv = [])
          law = argv.index("--law") ? argv[argv.index("--law") + 1] : nil
          rows = law ? ledger.select { |p| p["laws"].to_s.include?(law) } : ledger
          emit(command: "precedent list",
               precedents: rows.size,
               governing: rows.count { |p| p["status"] == "governing" },
               overruled: rows.count { |p| p["status"] == "overruled" },
               rows: rows.map { |p| { id: p["id"], status: p["status"], laws: p["laws"],
                                       ruling: p["ruling"].to_s.lines.first.to_s.strip[0, 100],
                                       adopted_by: p["adopted_by"] } })
          0
        end

        # A hard question answered by what the tradition already decided:
        # the precedent, its reasoning, what it cites, and what cites IT.
        def cite(argv)
          id = argv.first
          refuse("precedent cite", "no precedent id given", "an id from precedent list, e.g. P-001") if id.nil?
          row = ledger.find { |p| p["id"] == id }
          unless row
            warn "precedent: nothing named #{id}; precedent list names what the corpus has"
            exit(64)
          end

          citing = ledger.select { |p| p["cites"].to_s.include?(row["id"]) }
          emit(command: "precedent cite",
               precedent: row,
               cited_by: citing.map { |p| p["id"] },
               note: row["status"] == "overruled" ? "overruled; the row stays so the reason stays" : "governing; cite it before re-deciding")
          0
        end

        # An overruling is a ruling too: the old row stays, the reason stays,
        # and the new precedent's citation records which ruling it displaced.
        def overrule(argv)
          flags = argv.each_with_index.filter_map { |a, i| %w[--reason --evidence].include?(a) ? [a, argv[i + 1]] : nil }.to_h
          id = argv.find { |a| a.match?(/\AP-\d+\z/) }
          refuse("precedent overrule", "no precedent id given", "the id of the ruling being displaced") if id.nil?
          refuse("precedent overrule", "an overruling without a reason is a silent preference",
                 "--reason R, and --evidence FILE if the ruling carries proof") if flags["--reason"].nil?

          row = ledger.find { |p| p["id"] == id }
          refuse("precedent overrule", "nothing named #{id}", "precedent list names the corpus") if row.nil?
          return 0 if row["status"] == "overruled"

          new_id = "P-#{(ledger.map { |p| p['id'].delete_prefix('P-').to_i }.max + 1)}"
          new_row = {
            "id" => new_id,
            "date" => Time.now.utc.strftime("%Y-%m-%d"),
            "laws" => row["laws"],
            "question" => row["question"],
            "ruling" => flags["--reason"],
            "rationale" => "overrules #{id}: #{row['ruling'].to_s.lines.first.to_s.strip}",
            "cites" => [id] + (flags["--evidence"] ? [flags["--evidence"]] : []),
            "overrules" => [row["id"]],
            "adopted_by" => ["pub5"],
            "status" => "governing",
          }
          row["status"] = "overruled"
          ledger << new_row
          save(ledger)
          emit(command: "precedent overrule", overruled: id, precedent: new_row)
          0
        end

        def adopt(argv)
          flags = argv.each_with_index.filter_map { |a, i| %w[--tree].include?(a) ? [a, argv[i + 1]] : nil }.to_h
          id = argv.find { |a| a.match?(/\AP-\d+\z/) }
          refuse("precedent adopt", "no precedent id given", "the id being adopted") if id.nil?
          refuse("precedent adopt", "no tree given", "--tree TREE names the jurisdiction adopting") if flags["--tree"].nil?

          row = ledger.find { |p| p["id"] == id }
          refuse("precedent adopt", "nothing named #{id}", "precedent list names the corpus") if row.nil?
          row["adopted_by"] = Array(row["adopted_by"]) | [flags["--tree"]]
          save(ledger)
          emit(command: "precedent adopt", precedent: row["id"], adopted_by: row["adopted_by"])
          0
        end
      end
    end
  end
end
