# frozen_string_literal: true

require_relative "fix_helper"

# Moved from pub4 MASTER/test/test_proposal_scope.rb (36bb17ca45) and
# test_fix_repair_prompt_scope.rb (30aaecd1c8). The 2026-11-05 RAILS run
# asked for five Laws in one proposal over a 2,800-line stylesheet, and run 2
# lost 6 of 13 proposals to the range and 5 to dropped guards.
class FixScopeTest < Minitest::Test
  include FixHelper
  Scope = Fix::Scope

  def bundled
    [["NO_ASCII_LINE_ART", 6], ["NO_ASCII_LINE_ART", 8], ["SMALL_FILES", 1], ["LINE_HEIGHT_ON_SCALE", 541],
     ["TOUCH_TARGET_MIN", 681], ["LINE_HEIGHT_ON_SCALE", 865], ["MOBILE_FIRST", 913], ["MOBILE_FIRST", 1083],
     ["TOUCH_TARGET_MIN", 1671], ["MOBILE_FIRST", 1815], ["LINE_HEIGHT_ON_SCALE", 1950],
     ["LINE_HEIGHT_ON_SCALE", 1956]].map { |law, line| finding(law, line) }
  end

  def test_a_proposal_takes_one_scope_window_and_leaves_the_rest
    taken, deferred = Scope.narrow(bundled)

    lines = taken.map(&:line)
    assert_operator lines.max - lines.min, :<=, Scope::WINDOW
    refute_includes taken.map(&:law), :SMALL_FILES
    assert_equal bundled.size, taken.size + deferred.size
  end

  def test_adjacent_findings_of_several_laws_still_share_one_proposal
    near = [finding("MAGIC_COLOR", 474), finding("CONTRAST_TOKENS", 474), finding("EIGHT_PX_RHYTHM", 480)]

    taken, deferred = Scope.narrow(near + [finding("MOBILE_FIRST", 2400)])

    assert_equal near, taken
    assert_equal [2400], deferred.map(&:line)
  end

  def test_a_whole_file_law_goes_alone_after_the_windows
    groups = Scope.groups([finding("SMALL_FILES", 1), finding("SQUINT_TEST", 1), finding("MOBILE_FIRST", 3)])

    assert_equal [[:MOBILE_FIRST], [:SMALL_FILES], [:SQUINT_TEST]], groups.map { |g| g.map(&:law) }
  end

  def test_the_prompt_names_the_range_the_check_enforces_and_the_guards
    note = Scope.note([finding("ABC_SIZE", 93), finding("ABC_SIZE", 143)])

    assert_includes note, "between line 68 and line 168"
    assert_includes note, "Keep every guard"
    assert_equal Scope::GUARD_NOTE, Scope.note([finding("SMALL_FILES", 1)])
  end

  def test_a_change_outside_the_range_is_refused_and_a_call_site_edit_is_not
    old = "def compute_total(a)\n  a\nend\n#{"x = 1\n" * 60}compute_total(1)\nlast = 2\n"
    far = old.sub("last = 2", "last = 3")
    call_site = old.sub("compute_total(1)", "compute_total(2)")
    near = old.sub("  a\n", "  a + 0\n")

    assert_match(/changes lines 65-65, finding range is 1-27/, Scope.outside([finding("X", 2)], old, far))
    assert_nil Scope.outside([finding("X", 2)], old, call_site)
    assert_nil Scope.outside([finding("X", 2)], old, near)
  end

  def test_a_change_that_drops_a_guard_is_named
    old = "def run(report)\n  return unless report\n  store && store.save(report) if report.ready?\nend\n"
    dropped = "def run(report)\n  store.save(report)\nend\n"

    assert_match(/drops a/, Scope.dropped_guard(old, dropped))
    assert_nil Scope.dropped_guard(old, old.sub("store.save", "store.persist"))
  end
end
