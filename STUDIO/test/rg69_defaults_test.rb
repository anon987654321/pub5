# frozen_string_literal: true

require_relative "minitest_helper"

# RG-69 is one HTML file, one JS file and one stylesheet, and a person meets it
# through the defaults, not the sliders. Two things have gone wrong before and
# are worth holding still: the markup controls drifted from the values the
# engine boots with (so the panel showed one number and the machine played
# another), and a default style could name a pattern key the tables do not
# carry, which is silence rather than a wrong note.
#
# This reads the two source files as text and asserts they agree. It never runs
# the page: the sequencer is Tone.js and a browser, and the contract here is the
# boot state the sources declare, which is exactly what drifted.
class TestRg69Defaults < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  JS = File.join(ROOT, "rg69.js")
  HTML = File.join(ROOT, "rg69.html")

  # The controls whose markup default must equal the engine's boot default.
  CONTROLS = %w[bpm swing drive tape comp width reverb delay filter wobble vinyl crackle].freeze

  def js = @js ||= File.read(JS)
  def html = @html ||= File.read(HTML)

  def test_markup_controls_match_the_engine_boot_defaults
    aud = boot_aud
    CONTROLS.each do |name|
      assert_equal aud.fetch(name.to_sym), range_value(name),
                   "rg69.html ##{name} default and rg69.js aud_.#{name} disagree"
    end
  end

  def test_boot_patterns_exist_in_the_tables
    pattern = boot_pattern
    %w[d b k p].each do |lane|
      key = pattern.fetch(lane.to_sym)
      assert_includes pattern_keys(lane), key,
                      "boot pattern #{lane}=#{key.inspect} is not in the #{lane} table (silence)"
    end
  end

  def test_the_default_style_chip_names_a_declared_style
    chip = js[/find\(c=>c\.textContent==='([^']+)'\)/, 1]
    refute_nil chip, "no default style chip is selected in rg69.js"
    assert_includes style_names, chip, "default chip #{chip.inspect} names no STYLES entry"
  end

  # The point of the retune: the default is industrial techno over dilla's Blue
  # Hour material, so the grid is four-on-the-floor and the master is driven and
  # tight rather than swung and wet.
  def test_the_default_reads_as_industrial_techno
    aud = boot_aud
    assert_operator aud.fetch(:swing), :<=, 20, "industrial techno is on-grid, not swung"
    assert_operator aud.fetch(:drive), :>=, 60, "industrial techno wants a driven master"

    kick = boot_drum.fetch("k")
    [0, 4, 8, 12].each do |step|
      assert_operator kick[step], :>=, 0.9, "a four-on-the-floor kick is missing at step #{step}"
    end
  end

  private

  def boot_aud
    body = js[/let aud_=\{(.*?)\};/m, 1] or raise "no aud_ boot defaults in rg69.js"
    body.scan(/(\w+):([\d.]+)/).to_h { |key, value| [key.to_sym, value.to_f] }
  end

  def boot_pattern
    body = js[/let pat_=\{(.*?)\};/m, 1] or raise "no pat_ boot patterns in rg69.js"
    body.scan(/(\w+):'([^']+)'/).to_h { |lane, key| [lane.to_sym, key] }
  end

  def range_value(name)
    match = html.match(/id="#{Regexp.escape(name)}"\s+type="range"[^>]*\bvalue="([\d.]+)"/)
    raise "rg69.html has no range ##{name}" unless match

    match[1].to_f
  end

  # The keys a pattern table declares, read from the `const <TABLE>={ ... }`
  # block so a default can be checked against what the engine actually carries.
  def pattern_keys(lane)
    table = { "d" => "DRUM_PATTERNS", "b" => "BASS_PATS", "k" => "KEYS_PATS", "p" => "PAD_PATS" }
    name = table.fetch(lane)
    block = js[/const #{name}=\{(.*?)\n\};/m, 1] or raise "no #{name} table in rg69.js"
    block.scan(/^\s*'([^']+)':/).flatten
  end

  def style_names = js.scan(/\{n:'([^']+)'/).flatten

  def boot_drum
    block = js[/const DRUM_PATTERNS=\{(.*?)\n\};/m, 1] or raise "no DRUM_PATTERNS table"
    key = boot_pattern.fetch(:d)
    row = block[/'#{Regexp.escape(key)}':tpP\(\{(.*?)\}\)/m, 1] or raise "no drum pattern #{key}"
    row.scan(/(\w+):\[([^\]]*)\]/).to_h do |lane, list|
      [lane, list.split(",").map { |value| value.strip.empty? ? 0.0 : value.to_f }]
    end
  end
end
