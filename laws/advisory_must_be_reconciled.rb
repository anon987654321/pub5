# frozen_string_literal: true

# 875 of the corpus's Laws ride as advisory, and an agent under pressure
# reads advisory as ignorable - that is how the dmesg Law's own subject went
# missing while it sat in the index. The admission contract says advisory is
# the entry state, not a lesser state: the Law governs the files it reaches
# now, and enforcement arrives when the census and the operator's
# ratification do. The duty in between is reconciliation.
#
# The duty has a tree artifact: an answered advisory finding is recorded, and
# the recorded answer is the craft ledger's exemptions section, where an
# excused finding carries the reason it was granted and the review_by date it
# must be re-argued by. An exemption without that expiry is the unanswered
# finding this Law names, so the Law carries a deterministic adapter over the
# ledger's shape. Freshness (an expired review_by) stays the ln check's one
# assertion - two instruments asserting one property are two places for it to
# rot - and the Law owns the shape: every exemption row records which Law it
# excuses, when it was recorded, and when it must come back.
Law.define(:ADVISORY_MUST_BE_RECONCILED) do
  source "PLAN.md sections 5 and 19; registry/laws.yml admission contract; master/checks/data/craft_ledger.yml"
  path "master/checks/data/craft_ledger.yml"

  practice "- **Advisory is not ignorable.** A Law in advisory lifecycle still governs the files it " \
           "reaches: before a task lands, run the gate over the touched scope and answer every finding - " \
           "fix it, or record an exemption with an expiry. An advisory finding left unanswered in touched " \
           "scope is an unmet acceptance row, not a preference."

  bad_ledger = <<~BAD
    ceilings: {}
    exemptions:
      - id: no-inline-script-chat-face
        law: NO_INLINE_SCRIPT_BLOCK
        surface: MASTER web chat face
        reason: >-
          Face chat needs its live behaviour beside the markup it stipples.
        recorded: "2026-10-25"
  BAD
  good_ledger = <<~GOOD
    ceilings: {}
    exemptions:
      - id: no-inline-script-chat-face
        law: NO_INLINE_SCRIPT_BLOCK
        surface: MASTER web chat face
        reason: >-
          Face chat needs its live behaviour beside the markup it stipples.
        recorded: "2026-10-25"
        review_by: "2027-04-26"
  GOOD

  adapter(:structured_data, languages: %w[yaml],
          example_path: "master/checks/data/craft_ledger.yml",
          bad: bad_ledger, good: good_ledger) do |text, file|
    next [] unless file == "master/checks/data/craft_ledger.yml"

    findings = []
    rows = []
    row = nil
    in_exemptions = false
    text.each_line do |line|
      case line.chomp
      when /\Aexemptions:\s*\z/
        in_exemptions = true
      when /\A\S/
        in_exemptions = false
      when /\A\s{2}- id:\s*(.*?)\s*\z/
        rows << row if row
        row = in_exemptions ? { "id" => Regexp.last_match(1).delete_prefix('"').delete_suffix('"') } : nil
      when /\A\s{4}([a-z_]+):\s*(.*?)\s*\z/
        row&.store(Regexp.last_match(1), Regexp.last_match(2).delete_prefix('"').delete_suffix('"'))
      end
    end
    rows << row if row

    rows.each_with_index do |entry, index|
      number = index + 1
      %w[law recorded review_by].each do |field|
        next unless entry.fetch(field, "").empty?

        findings << finding(line: number,
                            message: "exemption #{entry['id']} records no #{field} - " \
                                     "#{field == 'review_by' ? 'an exemption without an expiry is an unanswered finding' : 'the exemption is not answerable'}")
      end
      next if !entry["recorded"].nil? && !entry["review_by"].nil? &&
              /\A\d{4}-\d{2}-\d{2}\z/.match?(entry["recorded"]) &&
              /\A\d{4}-\d{2}-\d{2}\z/.match?(entry["review_by"]) &&
              entry["recorded"] <= entry["review_by"]

      unless findings.any? { |f| f[:line] == number }
        findings << finding(line: number,
                            message: "exemption #{entry['id']} carries dates that do not parse or do not order " \
                                     "(recorded #{entry['recorded'].inspect}, review_by #{entry['review_by'].inspect})")
      end
    end
    findings
  end
end
