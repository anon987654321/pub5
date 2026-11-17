# frozen_string_literal: true

module Master
  module Fix
    class ArchitectureExploration
      # Candidate intake and local scoring, re-opening the class defined in
      # fix/architecture_exploration.rb: normalization of the model's answer
      # into grounded candidates, the evidence scorecard, the quality floors
      # and the near-duplicate gate. All private; the public surface stays in
      # fix/architecture_exploration.rb.
      private

      # One accepted candidate per lens id, in declared lens order; every
      # refusal is recorded with its reason and never silently dropped.
      def normalize(items, tree, grounded_evidence:, available_tests:)
        accepted = []
        rejected = []
        expected = LENSES.first(@count).to_h { |lens| [lens[:id], lens[:name]] }
        seen = Set.new
        Array(items).each do |raw|
          candidate = accepted_candidate(raw, tree, expected:, grounded_evidence:, available_tests:, seen:, accepted:, rejected:)
          next if candidate.nil?

          seen << candidate.fetch(:id)
          accepted << candidate
        end
        missing = expected.keys.to_set - seen
        rejected << "missing candidates: #{missing.to_a.sort.join(",")}" unless missing.empty?
        [accepted, rejected.first(80)]
      end

      # Full gate chain for one raw answer: identity, grounding, completeness,
      # then the near-duplicate check against everything already accepted.
      def accepted_candidate(raw, tree, expected:, grounded_evidence:, available_tests:, seen:, accepted:, rejected:)
        identified = identified_row(raw, expected, rejected, seen)
        return nil unless identified

        id, row = identified
        candidate = grounded_candidate(id, row, tree, expected:, grounded_evidence:, available_tests:, rejected:)
        return nil unless candidate

        duplicate = accepted.find { |other| near_duplicate?(other, candidate) }
        rejected << "#{id}: near-duplicate of #{duplicate[:id]}" if duplicate
        duplicate ? nil : candidate
      end

      # Shape, lens identity and uniqueness gates; a failed gate records its rejection.
      def identified_row(raw, expected, rejected, seen)
        unless raw.is_a?(Hash)
          rejected << "candidate was not an object"
          return nil
        end
        row = raw.transform_keys(&:to_s)
        id = row["id"].to_s
        unless expected[id] == row["lens"].to_s
          rejected << "#{id.empty? ? "unknown id" : id}: mismatched id/lens"
          return nil
        end
        if seen.include?(id)
          rejected << "#{id}: duplicate id"
          return nil
        end
        [id, row]
      end

      def grounded_candidate(id, row, tree, expected:, grounded_evidence:, available_tests:, rejected:)
        cited_evidence, evidence = grounded_paths(row["evidence_paths"], tree, false, grounded_evidence)
        cited_tests, tests = grounded_paths(row["test_paths"], tree, true, available_tests)
        changes = valid_changes(row["change_paths"], tree)
        gates = { evidence:, cited_tests:, tests:, changes:,
          benefits: clean_phrases(row["benefits"]), tradeoffs: clean_phrases(row["tradeoffs"]), risks: clean_phrases(row["risks"]) }
        reasons = rejection_reasons(row, gates)
        unless reasons.empty?
          rejected << "#{id}: #{reasons.join("; ")}"
          return nil
        end
        candidate_row(id, expected.fetch(id), row, gates)
      end

      # A candidate needs grounded evidence, a change path, concrete
      # consequences, complete fields, and any cited test anchor must exist
      # in the supplied inventory.
      def rejection_reasons(row, gates)
        fields = %w[title thesis core_boundary verification_plan rollback_plan law_alignment]
        missing = fields.select { |field| row[field].to_s.strip.empty? }
        reasons = []
        reasons << "no source excerpt/hash from the supplied evidence set" if gates[:evidence].empty?
        reasons << "no valid in-tree change path" if gates[:changes].empty?
        reasons << "missing concrete benefit, trade-off or risk" if gates[:benefits].empty? || gates[:tradeoffs].empty? || gates[:risks].empty?
        reasons << "missing fields #{missing.join(",")}" unless missing.empty?
        reasons << "test anchors were not present in the supplied inventory" if gates[:cited_tests].any? && gates[:tests].empty?
        reasons
      end

      def candidate_row(id, lens, row, gates)
        { id:, lens:, title: row["title"].to_s[0, 160],
          thesis: row["thesis"].to_s[0, 900], core_boundary: row["core_boundary"].to_s[0, 600],
          change_paths: gates[:changes], evidence_paths: gates[:evidence], test_paths: gates[:tests],
          verification_plan: row["verification_plan"].to_s[0, 900],
          rollback_plan: row["rollback_plan"].to_s[0, 600],
          law_alignment: row["law_alignment"].to_s[0, 500],
          benefits: gates[:benefits], tradeoffs: gates[:tradeoffs], risks: gates[:risks] }
      end

      # Valid in-tree paths first, then only those the supplied set grounds.
      def grounded_paths(items, tree, tests_only, supplied)
        cited = valid_paths(items, tree, tests_only)
        [cited, cited.select { |path| supplied.include?(path) }]
      end

      def valid_paths(items, tree, tests_only)
        Array(items).filter_map do |value|
          path = value.to_s.strip
          next if path.empty? || path.start_with?("/") || path.split("/").include?("..") || path.include?("\\")
          full = File.expand_path(path, @root)
          next unless inside?(full, tree) && File.file?(full) && !sensitive?(full)
          next if tests_only && !(path.include?("/test/") || path.include?("/tests/") || path.include?("/spec/"))
          relative(full)
        end.uniq.first(10)
      end

      def valid_changes(items, tree)
        Array(items).filter_map do |value|
          path = value.to_s.strip
          next if path.empty? || path.start_with?("/") || path.split("/").include?("..") || path.include?("\\")
          path if inside?(File.expand_path(path, @root), tree)
        end.uniq.first(10)
      end

      def score(row)
        source = row[:evidence_paths].empty? ? 0 : [8 + row[:evidence_paths].size * 4, SCORES.fetch(:source_evidence)].min
        tests = [row[:test_paths].size * 9, SCORES.fetch(:test_anchors)].min
        verification = verification_score(row)
        rollback = rollback_score(row[:rollback_plan])
        scope = scope_score(row)
        law = law_alignment_score(row[:law_alignment])
        tradeoff = tradeoff_analysis_score(row)
        parts = { source_evidence: source, test_anchors: tests, verification:,
          rollback:, scope:, law_alignment: law, tradeoff_analysis: tradeoff }
        parts.merge(total: parts.values.sum)
      end

      # Recognition of an executable verification plan, bounded by the weight table.
      def verification_score(row)
        verification = (row[:verification_plan].match?(/\b(run|test|assert|compare|measure|verify|ruby|bundle|rake)\b/i) ? 8 : 0) +
          (row[:test_paths].empty? ? 0 : 4) +
          (row[:verification_plan].match?(/\b(expected|regression|before|after|baseline)\b/i) ? 3 : 0)
        [verification, SCORES.fetch(:verification)].min
      end

      def rollback_score(rollback_text)
        rollback_text.match?(/\b(revert|restore|rollback|checkpoint|feature flag|reverse migration)\b/i) ? SCORES.fetch(:rollback) : (rollback_text.length >= 40 ? 7 : 0)
      end

      # Smaller change sets score higher; rewrite language is penalized.
      def scope_score(row)
        count = row[:change_paths].size
        scope = count.zero? ? 0 : (count <= 3 ? 12 : (count <= 6 ? 10 : (count <= 10 ? 7 : 3)))
        scope = [scope - 4, 0].max if row[:thesis].match?(/\b(rewrite from scratch|replace everything|big bang)\b/i)
        scope
      end

      def law_alignment_score(law_text)
        law_text.match?(/\b(preserv|law|constitution|existing behavior|backward.compatib|operator)\w*/i) ? SCORES.fetch(:law_alignment) : (law_text.length >= 40 ? 5 : 0)
      end

      def tradeoff_analysis_score(row)
        benefit_detail = row[:benefits].count { |text| text.length >= 24 }
        tradeoff_detail = row[:tradeoffs].count { |text| text.length >= 24 }
        consequence_terms = signature((row[:benefits] + row[:tradeoffs]).join(" ")).size
        [benefit_detail * 2 + tradeoff_detail * 2 + (consequence_terms >= 12 ? 2 : 0), SCORES.fetch(:tradeoff_analysis)].min
      end

      def quality_qualified?(candidate)
        card = candidate.fetch(:scorecard)
        card.fetch(:total) >= MIN_WINNER_SCORE &&
          QUALITY_FLOORS.all? { |dimension, floor| card.fetch(dimension) >= floor }
      end

      def clean_phrases(values)
        return [] unless values.is_a?(Array)
        values.filter_map do |value|
          phrase = value.to_s.strip.gsub(/\s+/, " ")
          next if phrase.length < 16
          phrase[0, 260]
        end.uniq.first(5)
      end

      def near_duplicate?(left, right)
        a = signature([left[:title], left[:thesis], left[:core_boundary],
          *left[:benefits], *left[:tradeoffs]].join(" "))
        b = signature([right[:title], right[:thesis], right[:core_boundary],
          *right[:benefits], *right[:tradeoffs]].join(" "))
        return false if a.empty? || b.empty?

        text_similarity = (a & b).size.to_f / (a | b).size
        left_paths = left[:change_paths].to_set
        right_paths = right[:change_paths].to_set
        path_similarity = if (left_paths | right_paths).empty?
                            0.0
                          else
                            (left_paths & right_paths).size.to_f / (left_paths | right_paths).size
                          end
        text_similarity >= 0.90 || (text_similarity >= 0.65 && path_similarity >= 0.80)
      end

      def signature(text)
        text.downcase.scan(/[a-z0-9_]{4,}/).reject do |word|
          %w[architecture boundary existing candidate preserve behavior plan system tree].include?(word)
        end.to_set
      end
    end
  end
end
