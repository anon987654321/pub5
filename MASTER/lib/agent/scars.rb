# frozen_string_literal: true

# bin/master scars - the casebook of scars, read as teaching memory.
#
# Every law was born from a failure. The tree writes reasons beside files
# and keeps its refutations; this command curates them into one memory a
# newcomer reads instead of re-learning the failure. `scars` lists the
# incidents; `scars --law NO_PUTS` shows the scars a law grew from; each
# row carries its citation, and a row whose citation is still pending says
# so instead of inventing one.

require "yaml"
require_relative "fast_gate"

module Master
  module Agent
    module Scars
      extend Base

      class << self
        include Base

        def run(argv)
          law = argv.index("--law") ? argv[argv.index("--law") + 1] : nil
          rows = load_yaml(data_path("incidents.yml")).fetch("incidents", [])
          rows = rows.select { |i| i["laws_born"].to_s.include?(law.to_s) || i["laws_governed"].to_s.include?(law.to_s) } if law

          emit(
            command: "scars",
            law: law,
            incidents: rows.size,
            rows: rows.map do |incident|
              {
                id: incident["id"],
                title: incident["title"],
                summary: incident["summary"].to_s.strip.lines.first.to_s.strip[0, 160],
                laws_governed: incident["laws_governed"],
                refuted_alternatives: incident["refuted_alternatives"],
                citation: incident["citation"],
                provenance_verified: !incident["citation"].to_s.match?(/pending|operator session record/),
              }
            end,
            note: "a scar without a verified citation is recorded as such; Chesterton's fence reads better with the scar attached than with a fake one",
          )
          0
        end
      end
    end
  end
end
