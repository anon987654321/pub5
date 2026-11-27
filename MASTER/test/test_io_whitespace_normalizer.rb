# frozen_string_literal: true

require_relative "test_helper"
require "prism"

# Applied to every committed write. This runs over source the agent is about to
# commit, and its one dangerous operation -- squeezing runs of internal spaces -- must
# not reach inside a string literal or a heredoc. A normalizer that rewrites the
# contents of a string changes what the program does, silently, on a code path
# whose whole purpose is to be unremarkable.
class TestWhitespaceNormalizer < Minitest::Test
  N = Master::Io::WhitespaceNormalizer

  def rb(source) = N.normalize(source, path: "x.rb")

  # --- the safe half, applied to every file type --------------------------

  def test_trailing_whitespace_goes
    assert_equal "a\nb\n", N.normalize("a   \nb\t\n")
  end

  def test_a_run_of_blank_lines_becomes_one
    assert_equal "a\n\nb\n", N.normalize("a\n\n\n\n\nb\n")
  end

  def test_a_single_blank_line_survives
    assert_equal "a\n\nb\n", N.normalize("a\n\nb\n")
  end

  def test_yaml_write_cleanup_preserves_scalar_values
    source = "# ---\nname: demo\nvalue: |\n  # ---\n  a  \n\n\n  b\n"
    out = N.normalize(source, path: "data.yml")

    refute out.start_with?("# ---")
    assert_includes out, "  # ---"
    assert_equal Psych.parse_stream(source).yaml, Psych.parse_stream(out).yaml
    assert_equal out, N.normalize(out, path: "data.yml")
  end

  def test_banners_keep_useful_titles_and_directives
    source = "# --- Public API ---\n# ===\n# --- frozen_string_literal: true\nname: example\n"
    out = N.normalize(source, path: "data.yml")

    assert_includes out, "# Public API\n"
    refute_includes out, "# ==="
    assert_includes out, "# --- frozen_string_literal: true"
    assert_equal Psych.parse_stream(source).yaml, Psych.parse_stream(out).yaml
  end

  def test_header_cleanup_does_not_touch_executable_body
    {
      "script.zsh" => ["#!/bin/zsh\n# --- Setup ---\n# =====\n", "cat <<'TEXT'\n# =====\n  a  \nTEXT\n"],
      "app.js" => ["// --- Setup ---\n// =====\n", "const x = " + 96.chr + "\n// =====\n  a  \n" + 96.chr + ";\n"],
      "theme.css" => ["/* --- Setup --- */\n/* ===== */\n", ".a { --value: '  '; }\n/* ===== */\n"],
    }.each do |path, (head, body)|
      source = head + body
      out = N.normalize(source, path:)
      refute_equal source, out
      assert out.end_with?(body), path
      assert_equal source.lines.size, out.lines.size, path
      assert_equal out, N.normalize(out, path:)
      assert_includes out, "Setup"
    end
  end

  def test_json_equivalence_does_not_hide_duplicate_key_or_number_changes
    refute N.data_equivalent?('{"a":1,"a":2}', '{"a":2}', path: "data.json")
    refute N.data_equivalent?('{"a":1.0}', '{"a":1}', path: "data.json")
    assert N.data_equivalent?('{"a": "  x  "}', '{"a":"  x  "}', path: "data.json")
  end

  def test_unknown_file_content_is_not_normalized_by_guesswork
    source = "record\t  \n\n\nvalue  "
    assert_equal source, N.normalize(source, path: "data.tsv")
    assert_equal source, N.normalize(source, path: "data.txt")
  end

  def test_markdown_write_cleanup_preserves_hard_breaks
    assert_equal "a  \nb\n", N.normalize("a  \nb \n", path: "README.md")
  end

  def test_leading_indentation_is_not_touched
    assert_equal "  a\n    b\n", N.normalize("  a\n    b\n")
  end

  def test_it_declines_to_work_on_nothing
    assert_equal "", N.normalize("")
    assert_nil N.normalize(nil)
    assert_equal 42, N.normalize(42)
  end

  # --- which files get the internal-space squeeze -------------------------

  def test_only_ruby_gets_the_internal_squeeze
    assert N.collapse_internal?("a.rb")
    assert N.collapse_internal?("A.RB"), "extension matching is case-insensitive"
    refute N.collapse_internal?("a.md")
    refute N.collapse_internal?("a.yml")
    refute N.collapse_internal?(nil), "with no path there is no way to know, so do the safe thing"
  end

  # Aligned tables in markdown and YAML are meaningful; squeezing them is a
  # content change, which is why the squeeze is extension-gated at all.
  def test_a_markdown_table_survives
    table = "| a   | b   |\n| --- | --- |\n"
    assert_equal table, N.normalize(table, path: "README.md")
  end

  def test_yaml_alignment_survives
    yaml = "a:   1\nbb:  2\n"
    assert_equal yaml, N.normalize(yaml, path: "data.yml")
  end

  # --- the squeeze itself -------------------------------------------------

  def test_aligned_assignments_are_squeezed_in_ruby
    assert_equal "a = 1\nbb = 2\n", rb("a  = 1\nbb = 2\n")
  end

  def test_indentation_survives_the_squeeze
    assert_equal "  x = 1\n", rb("  x  =  1\n")
  end

  # The whole reason the walker is a character loop and not a gsub.
  def test_a_string_literal_keeps_its_spaces
    assert_equal %(x = "a    b"\n), rb(%(x = "a    b"\n))
    assert_equal %(x = 'a    b'\n), rb(%(x = 'a    b'\n))
  end

  def test_a_string_with_an_escaped_quote_does_not_end_early
    source = %(x = "a \\" b    c"   + 1\n)
    assert_includes rb(source), %("a \\" b    c")
  end

  def test_a_double_quote_inside_single_quotes_is_not_a_string_start
    assert_equal %(x = 'a " b'\n), rb(%(x = 'a " b'   \n)),
                 "the walker treated a quote inside a literal as opening a string"
  end

  def test_spaces_outside_a_string_are_squeezed_while_the_string_is_left_alone
    assert_equal %(x = "a  b"\n), rb(%(x  =  "a  b"\n))
  end

  def test_a_comment_is_left_exactly_as_written
    assert_equal "x = 1 # a    b\n", rb("x  = 1 # a    b\n")
    assert_equal "# lined   up\n", rb("# lined   up\n")
  end

  # A heredoc body is data. The terminator is what closes it, and everything
  # between must survive untouched.
  def test_a_heredoc_body_is_data
    source = <<~RUBY
      x = <<~SQL
        select  a,    b
        from    t
      SQL
      y  = 1
    RUBY
    out = rb(source)

    assert_includes out, "select  a,    b"
    assert_includes out, "from    t"
    assert_includes out, "y = 1", "the squeeze did not resume after the heredoc closed"
  end

  def test_a_squiggly_and_a_dash_heredoc_both_close
    %w[<<~ <<- <<].each do |opener|
      source = "x = #{opener}SQL\n  a    b\nSQL\ny  = 1\n"
      out = rb(source)

      assert_includes out, "a    b", "#{opener} body was squeezed"
      assert_includes out, "y = 1", "#{opener} never closed, so the rest of the file was skipped"
    end
  end

  def test_a_quoted_heredoc_terminator_still_closes
    out = rb(%(x = <<~'SQL'\n  a    b\nSQL\ny  = 1\n))

    assert_includes out, "a    b"
    assert_includes out, "y = 1"
  end

  # --- properties ---------------------------------------------------------

  def test_normalizing_twice_changes_nothing_the_second_time
    [
      "a  =  1\n\n\n\nb = 2   \n",
      %(x = "a    b"  # c    d\n),
      "x = <<~SQL\n  a    b\nSQL\n",
    ].each do |source|
      once = rb(source)
      assert_equal once, rb(once), "the normalizer is not idempotent on #{source.inspect}"
    end
  end

  # The one property that makes this safe to run before every commit.
  def test_it_never_breaks_a_file_that_parsed
    sources = [
      "def a(b, c) = b + c\n",
      %(puts "a    b"\n),
      "x = <<~SQL\n  select  1\nSQL\n",
      "h = { a:  1, bb:  2 }\n",
      "x = %w[a  b]\n",
      "s = 'it\\'s'\n",
    ]

    sources.each do |source|
      assert Prism.parse(source).success?, "fixture does not parse: #{source.inspect}"
      out = rb(source)
      assert Prism.parse(out).success?, "normalizing broke a valid file:\n#{source.inspect}\n->\n#{out.inspect}"
    end
  end

  def test_it_never_grows_a_file
    source = "a  =  1\n\n\n\nb = 2   \n"
    assert_operator rb(source).length, :<=, source.length
  end

  def test_the_line_count_only_falls_where_blank_runs_collapse
    source = "a\n\n\n\nb\n"
    assert_equal 3, N.normalize(source).lines.size
  end
end
