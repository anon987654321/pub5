# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# The style stage of the /fix pass reads the marks operator-facing strings
# actually wear. The audit is scoped to the speaking trees, so a fixture tree
# holds the violations and the real tree stays out of the assertion.
class TestFixTypographyAudit < Minitest::Test
  Audit = Master::Fix::TypographyAudit

  def test_reports_the_marks_that_reached_a_person
    Dir.mktmpdir do |dir|
      write_cli_file(dir, 'lib/cli/fixture.rb', <<~RUBY)
        module Fixture
          LINE = "waiting for it\u2026"
          DASH = "ready -- go"
          FLAGS = "--dry-run and --trace"
          GLOB = Dir.glob("lib/**/*.rb")
        end
      RUBY

      report = Audit.new(root: dir).call

      assert_match(/\Astyle0: 2 findings, 1 non ascii punctuation, 1 prose double dash\z/, report.lines.first.chomp)
      assert_match(/lib\/cli\/fixture\.rb:2 non_ascii_punctuation/, report)
      assert_match(/lib\/cli\/fixture\.rb:3 prose_double_dash/, report)
      refute_match(/FLAGS/, report, "flags keep their hyphens")
      refute_match(/GLOB/, report, "globs keep their dots")
    end
  end

  def test_a_clean_scope_reads_clean
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib", "voice"))
      File.write(File.join(dir, "lib", "voice", "clean.rb"), <<~RUBY)
        module Clean
          LINE = "waiting for it... - the note"
        end
      RUBY

      assert_match(/\Astyle0: clean/, Audit.new(root: dir).call)
    end
  end

  def test_measures_long_terminal_output_literals_in_fix_sources
    Dir.mktmpdir do |dir|
      write_cli_file(dir, 'lib/fix/fixture.rb', <<~RUBY)
        module Fixture
          Master::Trace::Dmesg.status(
          "fix0",
          "This terminal status sentence is deliberately much too long for the operator display and should wrap naturally."
        )
        end
      RUBY

      report = Audit.new(root: dir).call
      assert_match(/terminal measure/, report)
      assert_match(/lib\/fix\/fixture\.rb:2 terminal_measure/, report)
    end
  end

  def test_typesetting_reads_plain_business_html_and_markdown_readme
    require File.expand_path("../law/definition", __dir__) unless defined?(::Law::Definition)
    require File.expand_path("../law/typesetting", __dir__) unless defined?(::Law::Typesetting)
    html = ::Law::Typesetting.each_text("<p>En lesbar plan.</p>", "BIZ/plan.html").to_a
    business_markdown = ::Law::Typesetting.each_text("# Plan\nEn lesbar plan.", "BIZ/research/bringhurst-strunk-research.md").to_a
    readme = ::Law::Typesetting.each_text("A readable paragraph.", "MASTER/README.md").to_a

    assert_equal "En lesbar plan.", html.first.first
    assert_equal "En lesbar plan.", business_markdown.last.first
    assert_equal "A readable paragraph.", readme.first.first
    assert_equal "nb", ::Law::Typesetting.locale("BIZ/plan.html")
    assert_equal "en", ::Law::Typesetting.locale("MASTER/README.md")
    assert ::Law::Typesetting::PATH.match?("BIZ/plan.html")
    assert ::Law::Typesetting::PATH.match?("BIZ/research/bringhurst-strunk-research.md")
    assert ::Law::Typesetting::PATH.match?("MASTER/README.md")
    assert ::Law::Typesetting::PATH.match?("TODO.md")
    assert ::Law::Typesetting::PATH.match?("OPENBSD/docs/operations.md")

    require File.expand_path("../law/prose", __dir__) unless defined?(::Law::Prose)
    assert ::Law::Prose::SCOPES.fetch("nb").match?("BIZ/research/bringhurst-strunk-research.md")
    assert ::Law::Prose::SCOPES.fetch("en").match?("MASTER/README.md")
    assert ::Law::Prose::SCOPES.fetch("en").match?("MASTER/docs/quality.md")
    assert ::Law::Prose::SCOPES.fetch("en").match?("MASTER/lib/cli/entry.rb")
    assert_includes ::Law.catalogue_entry("PROSE_OMIT_QUALIFIERS_NB").fetch("languages"), "markdown"
    assert_includes ::Law.catalogue_entry("PROSE_ACTIVE_VOICE_NB").fetch("languages"), "markdown"
  end

  def test_a_scope_that_is_not_there_is_not_an_error
    Dir.mktmpdir do |dir|
      assert_match(/\Astyle0: clean/, Audit.new(root: dir).call)
    end
  end

  private

  def write_cli_file(root, relative, content)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
