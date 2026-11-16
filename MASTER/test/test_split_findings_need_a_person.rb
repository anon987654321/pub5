# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/scan/law_tree"

# FileRepair can deliver one corrected file per answer. A change whose
# blast radius spans multiple files is not a one-file repair and must wait for
# structural review by a person. Active one-file examples use canonical Laws;
# the multi-file routing fixture is synthetic, not a retired size-rule finding.
class TestSplitFindingsNeedAPerson < Minitest::Test
  Laws = Master::Review::Scan::Laws

  def needs_a_person?(finding)
    violation = Master::Fix::Violation.from_finding(finding.to_h, file: "example.rb").to_h
    Master::Fix::RepairLoop.allocate.send(:needs_a_person?, violation)
  end

  def test_a_finding_whose_change_spans_multiple_files_waits_for_a_person
    finding = {
      law: "STRUCTURAL_REVIEW",
      line: 1,
      message: "the proposed repair writes a second source file",
      severity: :warning,
      blast_radius: { files_touched: 2 },
    }

    assert needs_a_person?(finding)
  end

  def test_flattening_a_data_file_is_a_person_s_change
    deep = "a:\n  b:\n    c:\n      d:\n        e:\n          f: 1\n"
    finding = Laws::ConfigHierarchyLaw.new.check(deep, path: "/repo/data/deep.yml").first

    assert needs_a_person?(finding)
  end

  def test_a_one_file_repair_still_goes_to_the_model
    finding = Laws::CouplerLaw.new.check("order.send(:recalculate)\n", path: "/repo/lib/a.rb").first

    refute needs_a_person?(finding)
  end
end
