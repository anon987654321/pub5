# frozen_string_literal: true

module Master
  module Fix
    # Single ranking primitive shared by LawOrder (which law to fix next)
    # and ConflictResolver (whether a fix's side effect is bad enough to
    # reject). Replaces BiasGuard#priority_score (LawOrder's prior use) and
    # a plain Severity.rank comparison (ConflictResolver's prior use) with
    # one formula that also weighs constitutional precedence and learned
    # fix quality, so both call sites agree on what "more important" means.
    module Priority
      module_function

      def score(law_id:, severity:, frequency: 1.0, age_days: 0.0,
                law_resolver: nil, laws_index: nil, quality: 0.5, tier2: false)
        sev = Master::SEVERITY_RANK.fetch(severity.to_sym, 1)
        law_rank = law_resolver ? law_resolver.precedence_index(law_resolver.law_for(law_id, laws_index:)) : 50
        # Earlier constitutional nodes are more foundational, so they score higher.
        law_component = (100 - law_rank).clamp(0, 100)
        density = sev * frequency.to_f * (1.0 + (age_days.to_f / 30.0))
        base = density + (law_component * 0.5) + (quality.to_f * 2.0)
        tier2 ? base + 50.0 : base
      end

      # True when +candidate+ outranks +baseline+. Both are score() kwarg hashes.
      def higher?(candidate, baseline)
        score(**candidate) > score(**baseline)
      end

      # Shared with ConflictResolver's prior private #build_rules_index --
      # both need the same law_id => law_entry map to resolve law_for.
      # A root's laws.yml may hold plain registry entries (statement plus a
      # violates_law tag, no constitutional node); they still rank through
      # their tag, so the index reads the document's own entries rather than
      # only the normative catalogue law_entries_in selects.
      def laws_index(root:)
        Master.laws_document(root:)
          .filter_map do |id, row|
            next unless row.is_a?(Hash)
            next unless row["statement"] || row["violates_law"] || row["supports_law"]

            [id.to_s, row.merge("id" => id.to_s)]
          end.to_h
      end
    end
  end
end
