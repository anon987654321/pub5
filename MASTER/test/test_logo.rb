# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../tools/logo"

# The vector logo generator renders on demand. Its marks were once shipped in
# BIZ/fetat; Johann rejected that set as ugly and the files were removed, so
# nothing here asserts tree state — only that the generator itself behaves.
class TestLogo < Minitest::Test
  def test_render_is_an_svg_with_a_stroke_group_and_viewbox
    body = Master::Tools::Logo.render(motif: "fetat_hands", variant: "pure_symbol", seed: "probe")

    assert body.start_with?(%(<?xml version="1.0" encoding="UTF-8"?>\n<svg))
    assert_includes body, 'viewBox="0 0 512 512"'
    assert_includes body, 'stroke="#211C15"'
    refute_includes body, "M 000", "no malformed coordinate"
  end

  def test_same_seed_is_byte_identical_and_a_different_seed_differs
    first = Master::Tools::Logo.render(motif: "fetat_hands", variant: "pure_symbol", seed: "probe")
    again = Master::Tools::Logo.render(motif: "fetat_hands", variant: "pure_symbol", seed: "probe")
    other = Master::Tools::Logo.render(motif: "fetat_hands", variant: "pure_symbol", seed: "other")

    assert_equal first, again
    default = Master::Tools::Logo.render(motif: "fetat_hands", variant: "pure_symbol")
    assert_equal default, Master::Tools::Logo.render(motif: "fetat_hands", variant: "pure_symbol"),
                 "default seed also derives deterministically"
    refute_equal first, other
  end

  def test_unknown_variant_is_refused_not_rendered_quietly
    error = assert_raises(ArgumentError) do
      Master::Tools::Logo.render(motif: "fetat_hands", variant: "neon_glitch")
    end
    assert_match(/unknown variant/, error.message)
  end

  def test_cli_writes_all_five_variants
    Dir.mktmpdir do |dir|
      out, err, status = Open3.capture3(RbConfig.ruby, File.expand_path("../tools/logo.rb", __dir__), "--out", dir)
      assert status.success?, err

      lines = out.split("\n")
      assert_equal 5, lines.size
      lines.each { |path| assert File.file?(path) }
    end
  end
end
