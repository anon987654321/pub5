# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "minitest_helper"
require_relative "../photograph/selfies_gallery"

# The gallery's manifest is the one generated file the page reads. These tests
# exercise the real generator against real files on disk: what it scans, how it
# pairs a still with its animation, and the shape the page depends on.
class TestSelfiesGallery < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @lora = File.join(@dir, "lora")
    @out = File.join(@dir, "lora", "selfies-manifest.js")
    FileUtils.mkdir_p(@lora)
  end

  def teardown
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  def build(**options)
    Studio::Visual::SelfiesGallery.new(root: @lora, out: @out, **options).build
  end

  def touch(name, body = "x")
    path = File.join(@lora, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  def test_a_still_becomes_an_item_named_for_its_subject
    touch("postpro_ragnhild_selfie_01_v1.jpg")
    manifest = build

    assert_equal 1, manifest.fetch("count")
    assert_equal ["ragnhild"], manifest.fetch("subjects")
    item = manifest.fetch("items").fetch(0)
    assert_equal "still", item.fetch("kind")
    assert_equal "ragnhild", item.fetch("subject")
    assert_equal "ragnhild selfie 01", item.fetch("caption")
  end

  def test_a_film_is_paired_with_the_still_it_animates
    touch("ragnhild_selfie_01.jpg")
    touch("ragnhild_selfie_01.mp4")

    items = build.fetch("items")
    film = items.find { |item| item.fetch("kind") == "film" }
    refute_nil film, "the animation beside the still is not listed"
    assert film.fetch("src").end_with?("ragnhild_selfie_01.mp4")
    assert film.fetch("poster").end_with?("ragnhild_selfie_01.jpg"),
           "the film should carry its still as a poster"
  end

  def test_the_scored_cut_wins_over_the_silent_original
    touch("ragnhild_selfie_01.jpg")
    touch("ragnhild_selfie_01.mp4")
    touch("ragnhild_selfie_01_audio.mp4")

    film = build.fetch("items").find { |item| item.fetch("kind") == "film" }
    assert film.fetch("src").end_with?("ragnhild_selfie_01_audio.mp4"),
           "the cut with the soundtrack laid under it should be preferred"
  end

  def test_a_film_with_no_still_is_still_listed
    touch("ragnhild_film_20260101T000000_abc.mp4")

    film = build.fetch("items").find { |item| item.fetch("kind") == "film" }
    refute_nil film, "a film with no still beside it is dropped from the gallery"
  end

  def test_subject_filter_narrows_the_series
    touch("ragnhild_selfie_01.jpg")
    touch("merethe_selfie_01.jpg")

    manifest = build(subject: "merethe")
    assert_equal ["merethe"], manifest.fetch("subjects")
    assert_equal 1, manifest.fetch("items").length
  end

  def test_it_never_scans_a_symlink_out_of_the_tree
    outside = File.join(@dir, "outside_selfie_01.jpg")
    File.write(outside, "x")
    File.symlink(outside, File.join(@lora, "ragnhild_selfie_09.jpg"))

    assert_empty build.fetch("items"), "a symlinked render must not enter the manifest"
  end

  def test_the_manifest_is_loadable_javascript_naming_the_global
    touch("ragnhild_selfie_01.jpg")
    build

    body = File.read(@out)
    assert_includes body, "window.STUDIO_SELFIES"
    assert_includes body, "do not edit"
    # It must parse as the JS the page loads, not merely as JSON.
    assert system("node", "--check", @out, out: File::NULL, err: File::NULL),
           "manifest.js is not valid JavaScript"
  end

  def test_a_missing_lora_directory_is_a_clear_error
    FileUtils.remove_entry(@lora)
    error = assert_raises(ArgumentError) { build }
    assert_match(/not readable/, error.message)
  end

  def test_the_soundtrack_is_recorded_only_when_it_exists
    touch("ragnhild_selfie_01.jpg")
    touch("selfies-dilla.mp3")

    # The bed sits beside the manifest, so it is recorded by its bare name; the
    # page and the bed share the lora/ directory.
    manifest = build(soundtrack: "selfies-dilla.mp3")
    assert_equal "selfies-dilla.mp3", manifest.fetch("soundtrack")
  end
end

# The page itself, held to the same separation and no-inline rules the RG-69
# browser contract pins: page, styles and application code are separate assets,
# the carousel library is version-pinned, and the script builds nodes rather
# than setting innerHTML or evaluating strings.
class TestSelfiesBrowserContract < Minitest::Test
  def studio_root
    File.expand_path("..", __dir__)
  end

  def test_selfies_assets_are_separate_and_resolve
    html_path = File.join(studio_root, "lora", "selfies.html")
    css_path = File.join(studio_root, "lora", "selfies.css")
    js_path = File.join(studio_root, "lora", "selfies.js")
    [html_path, css_path, js_path].each { |path| assert File.file?(path), "missing #{path}" }

    html = File.read(html_path)
    assert_match(/<html[^>]+lang=["']en["']/i, html)
    assert_match(/<meta\s+charset=["']?utf-8/i, html)
    assert_includes html, 'href="selfies.css"'
    assert_includes html, 'src="selfies.js"'
    assert_includes html, 'href="#main-content"'
    assert_includes html, 'id="main-content"'
    refute_match(/<style\b|<script(?![^>]*\bsrc=)/i, html)
    refute_match(/\sstyle=["']/i, html)

    javascript = File.read(js_path)
    refute_match(/\.innerHTML\b|\beval\s*\(/, javascript)
    assert_includes javascript, "document.createElement"
    assert_includes File.read(css_path), "prefers-reduced-motion"
    assert_includes File.read(css_path), ":focus-visible"
  end

  def test_the_carousel_library_is_vendored_and_version_pinned
    vendor = File.join(studio_root, "vendor", "swiper")
    js = File.join(vendor, "swiper-bundle.min.js")
    css = File.join(vendor, "swiper-bundle.min.css")
    assert File.file?(js), "swiper-bundle.min.js is not vendored"
    assert File.file?(css), "swiper-bundle.min.css is not vendored"
    assert_match(/Swiper 11\.\d+\.\d+/, File.read(js))
    assert_match(/Swiper 11\.\d+\.\d+/, File.read(css))

    html = File.read(File.join(studio_root, "lora", "selfies.html"))
    assert_includes html, "../vendor/swiper/swiper-bundle.min.js"
    assert_includes html, "../vendor/swiper/swiper-bundle.min.css"
  end

  def test_the_page_names_the_generated_manifest_and_bed
    html = File.read(File.join(studio_root, "lora", "selfies.html"))
    assert_includes html, 'src="selfies-manifest.js"'
    assert_includes html, "selfies-dilla.mp3"
  end
end
