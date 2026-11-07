# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../master/fix/scan"
require_relative "../../master/fix/report"

# The boot: the ident and build lines, the census totals, one device line
# per Law that found something, the fix0 device's dry-run census, and the
# root the scan ends on.
class ReportBootTest < Minitest::Test
  include TestHelper

  ROOT = "/repo/pub5"

  def result(findings, files: 10)
    Fix::Scan::Result.new(findings:, files:, scanned: files, seconds: 1.0, cached_tree: false)
  end

  def finding(law, file, line = 1, message = nil)
    Law::Finding.new(law, file, line, "text", message)
  end

  def law_row(id, autofix: "review")
    Law::Definition.new({ id:, scope: :line, tags: [], languages: %w[ruby], surfaces: [], adapters: [],
                          reads_comments: false }, { "autofix" => autofix, "lifecycle" => "advisory" })
  end

  def boot(result, laws, dry_run: false, repair: nil, held: [])
    Fix::Report.boot(result, laws:, scope: ".", root: ROOT, dry_run:, repair:, held:)
  end

  def test_boot_opens_with_the_ident_the_build_line_and_the_totals
    text = boot(result([]), [])
    lines = text.lines.map(&:chomp)
    assert_match(/\AOpenBSD pub5 \(GENERIC\) #0: [A-Z][a-z]{2} /, lines[0])
    assert_equal "    root@fix:#{ROOT}", lines[1]
    assert_equal "total findings = 0", lines[2]
    assert_equal "files scanned = 10", lines[3]
    assert_equal "files dirty = 0", lines[4]
    assert_equal "mainbus0 (root): pub5", lines[5]
    assert_equal "cpu0 at mainbus0: 0 laws", lines[6]
    assert_equal "root on scan.json", lines.last
  end

  def test_a_finding_law_attaches_as_a_device_with_its_census
    laws = [law_row(:TYPOGRAPHIC_GRID)]
    text = boot(result([finding(:TYPOGRAPHIC_GRID, "AGENTS.md", 76)]), laws)
    assert_includes text, "grid0 at mainbus0: TYPOGRAPHIC_GRID\n"
    assert_includes text, "grid0: 1 findings in 1 files\n"
    refute_includes text, "fix0 at mainbus0"
  end

  def test_a_law_outside_the_table_answers_to_its_leading_word_and_a_second_takes_the_next_unit
    laws = [law_row(:MANY_ARGUMENTS), law_row(:MANY_RETURNS)]
    findings = [finding(:MANY_ARGUMENTS, "a.rb"), finding(:MANY_RETURNS, "b.rb")]
    text = boot(result(findings), laws)
    assert_includes text, "many0 at mainbus0: MANY_ARGUMENTS\n"
    assert_includes text, "many1 at mainbus0: MANY_RETURNS\n"
  end

  def test_the_quote_device_names_its_transform
    laws = [law_row(:QUOTES_BY_LOCALE)]
    text = boot(result([finding(:QUOTES_BY_LOCALE, "config/locales/nb.yml")]), laws)
    assert_includes text, "quote0: \"...\" -> «...»\n"
  end

  def test_the_abc_device_names_its_ratchet_from_the_findings
    laws = [law_row(:ABC_SIZE)]
    found = finding(:ABC_SIZE, "lib/dense.rb", 9, "ABC size 41.2 for #dense (A=9 B=10 C=9, ratchet 40) - extract")
    assert_includes boot(result([found]), laws), "abc0: complexity above ratchet 40\n"
  end

  def test_the_var_device_reports_vendor_noise_and_what_it_is_not_configured_for
    laws = [law_row(:NO_VAR)]
    found = [finding(:NO_VAR, "rails/public/vendor/x.min.js"), finding(:NO_VAR, "app.js")]
    text = boot(result(found), laws)
    assert_includes text, "var0: minified vendor javascript\n"
    assert_includes text, "var0: not configured\n"
  end

  def test_fix0_counts_the_repair_and_says_what_it_leaves
    laws = [law_row(:TRAILING_WHITESPACE, autofix: "automatic")]
    held = [finding(:NO_VAR, "vendor/x.js"), finding(:ABC_SIZE, "lib/dense.rb")]
    text = boot(result([finding(:TRAILING_WHITESPACE, "a.rb")]), laws,
                dry_run: true, repair: 408, held:)
    assert_includes text, "fix0 at mainbus0: dry-run\n"
    assert_includes text, "fix0: 408 files would be repaired\n"
    assert_includes text, "fix0: nothing written outside tmp/fix\n"
    assert_includes text, "fix0: vendor and high-complexity left not configured\n"
  end

  def test_fix0_names_the_review_lane_when_the_held_are_not_all_noise
    laws = [law_row(:TRAILING_WHITESPACE, autofix: "automatic")]
    held = [finding(:LONG_LINE, "lib/long.rb")]
    text = boot(result([finding(:TRAILING_WHITESPACE, "a.rb")]), laws,
                dry_run: true, repair: 1, held:)
    assert_includes text, "fix0: 1 findings left to the review lane\n"
  end

  def test_census_splits_the_transform_owned_findings_from_the_held
    laws = [law_row(:TRAILING_WHITESPACE, autofix: "automatic"), law_row(:BLANK_LINE_RUN)]
    findings = [finding(:TRAILING_WHITESPACE, "a.rb"), finding(:TRAILING_WHITESPACE, "a.rb", 2),
                finding(:TRAILING_WHITESPACE, "b.rb"), finding(:BLANK_LINE_RUN, "c.html")]
    repair, held = Fix::Report.census(result(findings), laws)
    assert_equal 2, repair
    assert_equal [finding(:BLANK_LINE_RUN, "c.html")], held
  end
end
