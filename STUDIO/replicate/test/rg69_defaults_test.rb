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
  ROOT = File.expand_path("../..", __dir__)
  JS = File.join(ROOT, "dilla", "rg69", "rg69.js")
  HTML = File.join(ROOT, "dilla", "rg69", "rg69.html")

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

  # The bug this holds still: initAudio() ended with randomizeFX(), so every
  # load rolled 2–5 effects per bus plus 3–8 on the master from a pool that
  # reaches Chebyshev 30, Distortion 0.8, BitCrusher 2 bits and PitchShift ±12
  # — at wet. A bad roll produced a crushed, detuned master, which read as
  # "unusable and inaudible". The boot must now install one fixed chain.
  def test_html_scripts_are_deferred_in_dependency_order
    assert_match(/<script src="\.\.\/vendor\/tone\/Tone\.min\.js" defer><\/script>/, html)
    assert_match(/<script src="rg69\.js" defer><\/script>/, html)
  end

  def test_welcome_gate_releases_the_interface_before_audio_initialization_finishes
    welcome = js[/\$id\('welcome-start'\)\.addEventListener\('click',async\(\)=>\{(.*?)\n\}\);/m, 1]
    refute_nil welcome
    assert_operator welcome.index("dismissWelcome();"), :<, welcome.index("await startPlayback(activationPromise);")
  end

  def test_panic_resets_visual_and_transport_handles_for_a_clean_restart
    panic = js[/\$id\('panic'\)\.addEventListener\('click',\(\)=>\{(.*?)\n\}\);/m, 1]
    refute_nil panic
    assert_includes panic, "st_.rafId=null;"
    assert_includes panic, "st_.transportId=null;"
  end

  def test_percussion_synthesizers_receive_their_correct_tonejs_arguments
    assert_includes js, "synths.kickClk.triggerAttackRelease(thirtySecond,rt,vl*0.3)"
    assert_includes js, "synths.snare.triggerAttackRelease(eighth,rt,vl)"
    assert_includes js, "synths.clap.triggerAttackRelease(sixteenthDuration,rt,vl)"
    assert_includes js, "synths.hat.triggerAttackRelease(200,sixteenthDuration,rt,vl)"
    assert_includes js, "synths.open.triggerAttackRelease(200,eighth,rt,vl)"
    refute_match(/synths\.(?:kickClk|snare|clap|hat|open)\.triggerAttackRelease\(rt,vl/, js)
  end

  def test_keyboard_shortcuts_work_from_welcome_and_range_controls
    handler = js[/function handleKeys\(e\)(.*?)\n\}/m, 1] or raise "no handleKeys"
    assert_includes handler, "$id('welcome-start').click()"
    assert_includes handler, "toggleTrackMute"
    refute_includes handler, "if(e.target.tagName==='INPUT'||e.target.tagName==='SELECT')return;"
    assert_includes js, "chip.addEventListener('keydown'"
  end

  def test_welcome_overlay_does_not_swallow_advertised_shortcuts
    handler = js[/function handleKeys\\(e\\)(.*?)\\n\\}/m, 1] or raise "no handleKeys"
    assert_includes handler, "k==='p'"
    assert_includes handler, "const supportedShortcut=['s','r','e','l','t','m'].includes(k)"
    assert_includes handler, "dismissWelcome();"
  end

  def test_sliders_update_without_trailing_debounce
    assert_includes js, "let fxUpdateFrame=null;"
    assert_includes js, "out.textContent=Math.round(v)"
    assert_includes js, "scheduleFXUpdate()"
    refute_match(/const handler=debounce\(\(\)=>\{\s*const v=parseFloat\(inp.value\)/, js)
  end

  def test_transport_callback_defers_visual_work_to_one_animation_loop
    body = js[/function scheduleLoop\(time\).*?(?=\nlet stepUiByIndex)/m] or raise "no scheduleLoop"
    refute_includes body, "analyser.getValue()"
    refute_includes body, "requestAnimationFrame"
    assert_includes body, "st_.uiDirty=true"

    assert_includes js, "function updateVisuals()"
    refute_includes js, "function updateVU()"
    refute_includes js, "function drawViz()"
  end

  def test_audio_context_resume_is_invoked_directly_in_trusted_click_handlers
    welcome = js[/\$id\('welcome-start'\)\.addEventListener\('click',async\(\)=>\{(.*?)\n\}\);/m, 1]
    play = js[/\$id\('play'\)\.addEventListener\('click',async\(\)=>\{(.*?)\n\}\);/m, 1]
    refute_nil welcome
    refute_nil play
    assert_match(/const activationPromise=Tone\.start\(\);\s*await startPlayback\(activationPromise\);/, welcome)
    assert_match(/const activationPromise=Tone\.start\(\);\s*await startPlayback\(activationPromise\);/, play)
    assert_includes js, "async function initAudio(activationPromise)"
  end

  def test_transport_callback_uses_numeric_note_durations
    body = js[/function triggerNotes\(.*?(?=\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    refute_match(/triggerAttackRelease\([^;]*['"](?:8n|2n|16n|32n)['"]/, body,
                 "musical duration strings must not be parsed inside scheduled callbacks")
    %w[eighth thirtySecond sixteenthDuration half].each do |duration|
      assert_includes body, duration
    end
  end

  def test_live_and_offline_audio_graphs_do_not_require_audio_worklets
    refute_includes js, "Tone.FrequencyShifter",
                    "FrequencyShifter loads an AudioWorklet from a blob URL and fails on opaque origins"
    refute_includes js, "new Tone.PitchShift",
                    "PitchShift is excluded from the bounded random FX pool"
  end

  def test_randomized_fx_are_bounded_and_do_not_allocate_unused_master_effects
    body = js[/function randomizeFX\(\).*?(?=\nasync function exportWAV)/m] or raise "no randomizeFX"
    assert_includes body, "const num=isMaster?0:1+Math.floor(Math.random()*2)"
    assert_includes body, "masterFX=[]"
    refute_match(/3\+Math\.floor\(Math\.random\(\)\*6\)/, body)
  end

  def test_boot_installs_a_fixed_chain_and_never_randomizes
    init = js[/async function initAudio\(\).*?(?=\n(?:async )?function )/m] or raise "no initAudio"
    assert_includes init, "installDefaultFX()"
    refute_includes init, "randomizeFX()",
                    "initAudio must not randomize the effect chain at boot"

    # The only remaining call to randomizeFX is the explicit randomize() action.
    assert_equal 1, js.scan(/randomizeFX\(\);/).size,
                 "randomizeFX must be reachable only from the explicit randomize() action"
  end

  def test_every_default_fx_parameter_is_a_literal_so_boots_are_repeatable
    body = js[/function createDefaultFX\(\)\{(.*?)\n\}/m, 1] or raise "no createDefaultFX"
    refute_includes body, "Math.random", "a default effect parameter must be fixed, not rolled"
    refute_match(/\brnd\(/, body, "a default effect parameter must be fixed, not rolled")

    # The curated chain still uses real effects, not an empty passthrough.
    %w[Tone.Chorus Tone.Distortion Tone.Freeverb Tone.FeedbackDelay Tone.StereoWidener].each do |fx|
      assert_includes body, fx, "the fixed chain should include #{fx}"
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
