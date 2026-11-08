# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

# The constitution measures itself. MASTER/checks/data/constitutional_budget.yml
# carries a constitution_lines ceiling over MASTER/data/laws.yml under the same
# only-ratchets-down contract its scan targets answer to (convergence.yml
# workstream constitution_self_budget). A line added without an equal removal
# fails here; the ceiling moves down only, in the commit that removed the lines.
class TestConstitutionalBudget < Minitest::Test
  ROOT = Master::REPO_ROOT
  BUDGET_PATH = File.join(ROOT, "MASTER", "checks", "data", "constitutional_budget.yml")
  LAWS_PATH = File.join(ROOT, "MASTER", "data", "laws.yml")

  def budget
    @budget ||= YAML.safe_load_file(BUDGET_PATH)
  end

  def constitution_budget
    budget&.dig("constitution_lines") || {}
  end

  def law_lines
    count = 0
    File.foreach(LAWS_PATH) { count += 1 }
    count
  end

  def test_ceiling_row_names_the_constitution_with_a_positive_integer
    assert_equal "MASTER/data/laws.yml", constitution_budget["target"]
    ceiling = constitution_budget["ceiling"]
    assert_instance_of Integer, ceiling, "constitution_lines.ceiling must be an integer"
    assert_operator ceiling, :>, 0
  end

  def test_constitution_fits_its_ceiling
    ceiling = constitution_budget["ceiling"]
    count = law_lines

    assert count <= ceiling,
           "laws.yml is #{count} lines against a #{ceiling}-line ceiling (+#{count - ceiling}) - " \
           "remove at least #{count - ceiling} lines and lower the ceiling in the same commit; " \
           "the constitution only ratchets down"
  end

  def test_ceiling_only_ratchets_down
    committed, status = Master::Io::Exec.capture2e("git", "-C", ROOT, "show",
                                                   "HEAD:MASTER/checks/data/constitutional_budget.yml")
    skip("initial revision owns the first ceiling") unless status.success?

    previous = YAML.safe_load(committed)&.dig("constitution_lines")&.dig("ceiling")
    skip("no constitution_lines ceiling at HEAD yet") unless previous.is_a?(Integer)

    current = constitution_budget["ceiling"]
    assert current <= previous,
           "constitution_lines ceiling rose #{previous} -> #{current} - the ceiling only ratchets down"
  end
end
