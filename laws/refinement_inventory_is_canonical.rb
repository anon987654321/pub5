# frozen_string_literal: true

# The operator's style and cosmetic refinements were lore twice. pub4 tuned
# them into a canonical acceptance inventory - ninety rows, each with its
# contract, its proof surfaces and an acceptance state, completed only by
# recorded evidence - and the pub5 port cited UX027 and UX028 from memory
# while the inventory itself never crossed. Nothing failed, and the boot
# fell out of the tree. A port can lose a file; a Law refuses to lose the
# instrument. The inventory is the one acceptance list, and this Law keeps
# it whole: present in the tree, well-formed, counted, every row carrying
# the fields its acceptance depends on.
#
# The shape is read off the lines, not through a YAML loader: laws/ is not
# exempt from ONE_IMPLEMENTATION_PER_OPERATION, and a Law that parses its
# own subject through the operation it polices would need an exemption to
# survive its own census.
Law.define(:REFINEMENT_INVENTORY_IS_CANONICAL) do
  source "pub4 MASTER/data/ux_refinements.yml and test_ux_refinements_contract.rb (ec05e5d); PLAN.md section 19"
  path "registry/ux_refinements.yml"

  # The inventory leaving the tree is itself the finding, so the deletion
  # is loud. A tree adapter sees the repository's paths; its absence is the
  # miss, not a missing count.
  adapter(:repository_tree,
          bad: ["bin/master", "registry/laws.yml"],
          good: ["bin/master", "registry/ux_refinements.yml"]) do |paths|
    next [] if paths.include?("registry/ux_refinements.yml")

    [finding(line: 1,
             message: "registry/ux_refinements.yml is gone - the operator's refinements have no acceptance list")]
  end

  # Well-formedness: the header promises a count the rows must keep,
  # evidence_policy keeps the completion rule and the no-simulation policy,
  # and every row carries id, area, title, owner_trees, proof, contract and
  # state, with ids unique - a duplicate id makes two refinements one
  # addressable row, which is how acceptance answers get lost.
  bad_inventory = <<~BAD
    schema: 1
    catalogue_id: PUB5_UX_REFINEMENTS
    expected_count: 2
    evidence_policy:
      completion_rule: "A row is complete only when its owner records the required evidence."
      no_simulation: "A source-only review never counts as a passing runtime test."
    refinements:
      - id: UX001
        area: "input"
        title: "Immediate acknowledgement"
        owner_trees: ["master"]
        proof: ["unit"]
        contract: "A submitted turn gets one truthful acknowledgement."
        state: "acceptance_required"
      - id: UX001
        area: "input"
        title: "Duplicate id"
        owner_trees: ["master"]
        proof: ["unit"]
        state: "acceptance_required"
  BAD
  good_inventory = <<~GOOD
    schema: 1
    catalogue_id: PUB5_UX_REFINEMENTS
    expected_count: 1
    evidence_policy:
      completion_rule: "A row is complete only when its owner records the required evidence."
      no_simulation: "A source-only review never counts as a passing runtime test."
    refinements:
      - id: UX001
        area: "input"
        title: "Immediate acknowledgement"
        owner_trees: ["master"]
        proof: ["unit"]
        contract: "A submitted turn gets one truthful acknowledgement."
        state: "acceptance_required"
  GOOD

  adapter(:structured_data, languages: %w[yaml],
          example_path: "registry/ux_refinements.yml",
          bad: bad_inventory, good: good_inventory) do |text, file|
    next [] unless file == "registry/ux_refinements.yml"

    findings = []
    header = {}
    policy = {}
    rows = []
    row = nil
    text.each_line do |line|
      case line.chomp
      when /\A(schema|catalogue_id|expected_count):\s*(.*?)\s*\z/
        header[Regexp.last_match(1)] = Regexp.last_match(2)
      when /\A\s{2}(completion_rule|no_simulation|implementation_state):\s*(.*?)\s*\z/
        policy[Regexp.last_match(1)] = Regexp.last_match(2)
      when /\A\s+- id:\s*(UX\d{3})\s*\z/
        rows << row if row
        row = { "id" => Regexp.last_match(1) }
      when /\A\s{4,}([a-z_]+):\s*(.*?)\s*\z/
        row&.store(Regexp.last_match(1), Regexp.last_match(2))
      end
    end
    rows << row if row

    findings << finding(line: 1, message: "schema must be 1") unless header["schema"] == "1"
    unless header["catalogue_id"] == "PUB5_UX_REFINEMENTS"
      findings << finding(line: 1, message: "catalogue_id must be PUB5_UX_REFINEMENTS")
    end
    unless header["expected_count"].to_s.match?(/\A\d+\z/) && header["expected_count"].to_i == rows.size
      findings << finding(line: 1,
                          message: "expected_count #{header["expected_count"].inspect} does not match #{rows.size} rows")
    end
    %w[completion_rule no_simulation].each do |word|
      next unless policy.fetch(word, "").empty?

      findings << finding(line: 1, message: "evidence_policy #{word} is empty - the completion rule is what makes a row answerable")
    end

    seen = {}
    rows.each_with_index do |entry, index|
      number = index + 1
      if seen.key?(entry["id"])
        findings << finding(line: number, message: "duplicate id #{entry["id"]} - two refinements share one addressable row")
      end
      seen[entry["id"]] = true
      %w[area title owner_trees proof contract state].each do |field|
        next unless entry.fetch(field, "").empty?

        findings << finding(line: number, message: "row #{entry["id"]} is missing #{field}")
      end
    end
    findings
  end
end
