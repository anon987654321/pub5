# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "tmpdir"
require_relative "check_fixture"
require_relative "../../../MASTER/checks/lib/source/css_minify_integrity"

# Compile each app's entrypoint twice and compare.
#
# check_app joins its app name onto RAILS_ROOT, so a fixture reaches it as the
# relative path from there — no constant rewriting, and the check resolves the
# stylesheet exactly the way it does for a real app.
#
# Two failures are planted. An entrypoint that does not compile ships no
# stylesheet at all, and the check has to say which app rather than crash the
# run. The selector-loss half detects a dart-sass compressed-output bug the
# installed compiler no longer has, so no SCSS makes a selector disappear; the
# loss is planted in the compiler's output instead, which proves the comparison
# and not the compiler. The normalisation it rests on is tested too, because
# that is where its false positives came from.
class CssMinifyIntegrityCheckTest < Minitest::Test
  include CheckFixture

  CHECK = Deploy::CssMinifyIntegrityCheck

  # The check requires the compiler inside #run and reports itself inconclusive
  # when it is absent, so a test reaching check_app has to load it first or
  # every compile reads as a failure.
  SASS = begin
    require "sass-embedded"
    true
  rescue LoadError
    false
  end

  def setup
    skip "sass-embedded unavailable — the check reports itself inconclusive here" unless SASS
  end

  def check(scss, checker: CHECK.new, compiler: nil)
    Dir.mktmpdir do |dir|
      plant(dir, "app/assets/stylesheets/application.scss", scss)
      rel = Pathname.new(dir).relative_path_from(Pathname.new(CHECK::RAILS_ROOT)).to_s
      result = Deploy::CheckResult.new
      checker.send(:check_app, result, rel, compiler:)
      result
    end
  end

  def test_an_entrypoint_that_does_not_compile_fails_and_names_the_app
    result = check(%(@use "no-such-partial";\n.a { color: red; }\n))

    refute result.ok?, "an entrypoint that cannot compile passed"
    assert_match(/failed to compile/, result.failures.first)
    assert_match(/Sass::CompileError/, result.failures.first)
  end

  def test_the_same_entrypoint_passes_once_it_compiles
    result = check(".a, .b, .c { color: red; }\n")

    assert result.ok?, result.failures.join(", ")
    assert_equal 1, result.checks_ran
  end

  def test_compressed_stylesheet_is_indexed_once_per_app
    checker = CHECK.new
    calls = 0
    original = checker.method(:selector_set)
    checker.define_singleton_method(:selector_set) do |css|
      calls += 1
      original.call(css)
    end
    groups = (1..30).map do |index|
      ".card-#{index}, .listing-#{index}, .story-#{index} { width: #{index}px; }"
    end

    result = check(groups.join("\\n"), checker:)

    assert result.ok?, result.failures.join(", ")
    assert_equal 1, calls, "the compressed selector index is built once per app"
  end

  # A long compound-selector list is the shape the check was written for. Every
  # item survives compression here, which is the state of the compiler rather
  # than of the check.
  def test_a_long_compound_selector_list_survives_compression
    selectors = (1..30).map { |i| ".feed-card.listing-#{i} .feed-card-avatar" }
    result = check("#{selectors.join(",\n")} { width: 32px; }\n")

    assert result.ok?, result.failures.join(", ")
  end

  def test_a_missing_selector_is_not_matched_by_a_longer_selector_prefix
    scss = ".feed-card.listing .feed-card-avatar, .post-card .avatar, .story .avatar { width: 32px; }\n"
    compiler = lambda do |entry:, load_paths:|
      expanded = Sass.compile(entry, load_paths:, style: :expanded).css
      compressed = Sass.compile(entry, load_paths:, style: :compressed).css
      compressed = compressed.sub(".feed-card.listing .feed-card-avatar", ".feed-card.listing .feed-card-avatar-large")
      { "expanded" => expanded, "compressed" => compressed }
    end

    result = check(scss, compiler:)

    refute result.ok?, "a longer selector prefix must not satisfy exact selector presence"
    assert_match(/lost selector\(s\) under compression/, result.failures.first)
    assert_match(/missing after compression: \[".feed-card.listing .feed-card-avatar"\]/, result.failures.first)
  end

    # The compiler cannot be made to lose a selector, but the comparison can be
  # handed compressed output that has lost one. This is the shape seen live:
  # the listing qualifier gone, leaving the bare avatar selector.
  def test_a_selector_that_loses_its_qualifier_under_compression_fails
    scss = ".feed-card.listing .feed-card-avatar, .post-card .avatar, .story .avatar { width: 32px; }\n"
    compiler = lambda do |entry:, load_paths:|
      expanded = Sass.compile(entry, load_paths:, style: :expanded).css
      compressed = Sass.compile(entry, load_paths:, style: :compressed).css
      compressed = compressed.sub(".feed-card.listing .feed-card-avatar", ".feed-card-avatar")
      { "expanded" => expanded, "compressed" => compressed }
    end

    result = check(scss, compiler:)

    refute result.ok?, "a selector that lost its qualifier passed"
    assert_match(/lost selector\(s\) under compression/, result.failures.first)
    assert_match(/missing after compression: \[".feed-card.listing .feed-card-avatar"\]/, result.failures.first)
  end

  def test_stylesheet_compilation_uses_the_process_group_deadline
    checker = CHECK.new
    captured = {}
    status = Object.new
    status.define_singleton_method(:success?) { true }
    payload = "CSS_MINIFY_RESULT:#{Base64.strict_encode64(JSON.generate(
      "expanded" => ".a { color: red; }", "compressed" => ".a{color:red}"
    ))}\n"

    runner = lambda do |*argv, **options|
      captured[:argv] = argv
      captured[:options] = options
      ["Sass warning: fixture warning\n#{payload}", status]
    end

    Master::Io::Exec.stub(:capture2e, runner) do
      result = checker.send(:compile_stylesheets, entry: "/tmp/application.scss",
                                         load_paths: ["/tmp/stylesheets"])
      assert_equal ".a{color:red}", result.fetch("compressed")
    end

    assert_equal CHECK::COMPILE_TIMEOUT, captured.fetch(:options).fetch(:timeout)
    assert_equal true, captured.fetch(:options).fetch(:raise_on_timeout)
    assert_includes captured.fetch(:argv), "-e"
    assert_includes captured.fetch(:argv), CHECK::SASS_COMPILER
  end

  def test_stylesheet_compilation_timeout_becomes_a_named_check_failure
    timeout = Master::Io::Exec::TimeoutError.new("timed out", result: ["", nil])
    result = nil

    Master::Io::Exec.stub(:capture2e, ->(*) { raise timeout }) do
      result = check(".a, .b, .c { color: red; }\n")
    end

    refute result.ok?
    assert_match(/failed to compile.*timed out after #{CHECK::COMPILE_TIMEOUT}s/, result.failures.first)
  end

  def test_a_missing_entrypoint_is_inconclusive_rather_than_clean
    result = Dir.mktmpdir do |dir|
      rel = Pathname.new(dir).relative_path_from(Pathname.new(CHECK::RAILS_ROOT)).to_s
      r = Deploy::CheckResult.new
      CHECK.new.send(:check_app, r, rel)
      r
    end

    assert_equal :inconclusive, result.outcome
    assert_match(/no application\.scss/, result.unchecked.first)
  end

  # Compressed output strips the whitespace around an explicit combinator and
  # keeps the single space that IS the descendant combinator. Normalising by
  # deleting all whitespace made `.a>b c` match `.a>bc`, and reported every such
  # selector as lost.
  def test_normalisation_collapses_combinators_without_joining_words
    check = CHECK.new

    assert_equal check.send(:normalize_selector, ".a>.b"), check.send(:normalize_selector, ".a > .b")
    assert_equal check.send(:normalize_selector, ".a+.b"), check.send(:normalize_selector, ".a  +  .b")
    refute_equal check.send(:normalize_selector, ".a .b"), check.send(:normalize_selector, ".a.b")
  end
end
