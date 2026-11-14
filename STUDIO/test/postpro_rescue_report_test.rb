# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../postpro/rescue"

class TestPostproRescueReport < Minitest::Test
  def test_report_uses_labels_instead_of_indentation_for_secondary_lines
    finding = Postpro::Rescue::Finding.new(
      code: :plastic,
      severity: :fixable,
      message: "little micro-texture",
      remedy: "use the portrait preset"
    )

    lines = Postpro::Rescue.report([finding])

    assert_includes lines, "rescue: remedy: use the portrait preset"
    refute lines.any? { |line| line.match?(/\Arescue: {2,}/) }
  end

  def test_out_of_reach_diagnostics_are_not_indented
    lines = Postpro::Rescue.report([])

    assert lines.any? { |line| line.start_with?("rescue: geometry") }
    assert lines.any? { |line| line.start_with?("rescue: focus") }
    assert lines.any? { |line| line.start_with?("rescue: expression") }
    refute lines.any? { |line| line.match?(/\Arescue: {2,}/) }
  end
end
