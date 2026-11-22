# frozen_string_literal: true

# bin/master taste - the operator's judgment, accumulating.
#
# RENDERED_VALUES makes palette, type and motion operator-owned, and a dozen
# seams re-ask the same question each session. This ledger records accepted
# and rejected renders as structured, versioned evidence the tree can cite -
# never to invent design, which stays forbidden, but to stop re-asking and
# to warn: you decided X on this date, and this new surface conflicts with
# it. Decisions live beside what they decide; this makes them queryable and
# lets them compound instead of resetting.

require "yaml"
require_relative "fast_gate"

module Master
  module Agent
    module Taste
      extend Base

      LEDGER = "taste_ledger.yml"

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          case action
          when "record" then record(argv.drop(1))
          when "query" then query(argv.drop(1))
          when "conflicts" then conflicts(argv.drop(1))
          else
            puts "usage: bin/master taste record --decision accepted|rejected --domain palette|type|motion --subject S [--rationale R]
       bin/master taste query [--domain D]
       bin/master taste conflicts --subject S [--surface FILE]"
            exit(64)
          end
        end

        def ledger_path
          @ledger_path ||= data_path(LEDGER)
        end

        def ledger
          File.file?(ledger_path) ? load_yaml(ledger_path) : { "schema" => 1, "decisions" => [] }
        end

        def save(ledger)
          File.write(ledger_path, YAML.dump(ledger))
        end

        def record(argv)
          opts = flags(argv, %w[--decision --domain --subject --rationale --surface])
          refuse("taste record", "a decision is accepted or rejected, never both, never neither",
                 "--decision accepted or --decision rejected") unless %w[accepted rejected].include?(opts["--decision"])
          refuse("taste record", "no domain given", "--domain palette, type or motion") if opts["--domain"].nil?
          refuse("taste record", "no subject given", "the surface the decision is about, e.g. --subject 'brgen wordmark spacing'") if opts["--subject"].nil?

          ledger = self.ledger
          entry = {
            "id" => "#{opts['--domain']}-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}",
            "at" => Time.now.utc.strftime("%Y-%m-%d"),
            "revision" => FastGate.head_revision,
            "decision" => opts["--decision"],
            "domain" => opts["--domain"],
            "subject" => opts["--subject"],
            "surface" => opts["--surface"],
            "rationale" => opts["--rationale"],
          }
          ledger["decisions"] = (ledger["decisions"] || []) + [entry]
          save(ledger)
          emit(command: "taste record", recorded: entry, ledger_size: ledger["decisions"].size)
          0
        end

        def query(argv)
          opts = flags(argv, %w[--domain])
          decisions = ledger.fetch("decisions", [])
          decisions = decisions.select { |d| d["domain"] == opts["--domain"] } if opts["--domain"]

          patterns = patterns(decisions)
          emit(
            command: "taste query",
            decisions: decisions.size,
            shown: decisions.last(20),
            accumulated_patterns: patterns,
            note: "a pattern the operator did not state is a proposal for the operator, never a rule the tree enforces; pedagogy propose turns these into rows",
          )
          0
        end

        # Conflicts: a new surface judged against the accumulated evidence.
        # The answer cites what was decided, when, and what it decided against.
        def conflicts(argv)
          opts = flags(argv, %w[--subject --surface])
          subject = opts["--subject"]
          refuse("taste conflicts", "no subject given", "the surface to judge, e.g. --subject 'dashboard uses 4 motion springs'") if subject.nil?

          decisions = ledger.fetch("decisions", [])
          domain = nil
          %w[palette type motion].each do |d|
            domain = d if subject.downcase.include?(d) ||
                          (d == "palette" && subject.match?(/colou?r|palette|accent/)) ||
                          (d == "type" && subject.match?(/font|type|wordmark|letterspacing/i)) ||
                          (d == "motion" && subject.match?(/motion|spring|transition|animate/i))
          end

          relevant = decisions.select { |d| domain.nil? || d["domain"] == domain }
          conflicts = relevant.filter_map do |d|
            overlap = subject_words(subject) & subject_words(d["subject"].to_s)
            next nil if overlap.empty?

            { decided: d["decision"], at: d["at"], subject: d["subject"], shared_terms: overlap,
              warning: "you decided #{d['decision']} on #{d['at']} for '#{d['subject']}'; this surface overlaps on #{overlap.join(', ')}" }
          end

          emit(
            command: "taste conflicts",
            subject:,
            domain_judged: domain,
            evidence_considered: relevant.size,
            conflicts:,
            verdict: conflicts.empty? ? "no recorded decision covers this surface; the question is genuinely new" :
                                       "a recorded decision speaks to this surface; cite it before re-asking the operator",
          )
          conflicts.empty? ? 0 : 1
        end

        private

        def flags(argv, names)
          argv.each_with_index.filter_map do |arg, i|
            names.include?(arg) && argv[i + 1] ? [arg, argv[i + 1]] : nil
          end.to_h
        end

        def subject_words(subject)
          subject.to_s.downcase.split(/\W+/).reject { |w| w.size < 4 }
        end

        def patterns(decisions)
          decisions.group_by { |d| [d["domain"], d["decision"]] }
                   .filter_map do |(domain, decision), rows|
            next nil if rows.size < 3

            { domain:, decision:, count: rows.size,
              subjects: rows.map { |r| r["subject"] }.first(5),
              pattern: "the operator has #{rows.size} recorded #{decision} decisions in #{domain}" }
          end
        end
      end
    end
  end
end
