# frozen_string_literal: true

require_relative "minitest_helper"
require "json"

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
  TONE = File.join(ROOT, "dilla", "vendor", "tone", "Tone.min.js")
  DILLA_DATA = File.join(ROOT, "dilla", "data", "dilla.json")

  # The controls whose markup default must equal the engine's boot default.
  CONTROLS = %w[bpm swing drive tape comp width reverb delay filter wobble vinyl crackle].freeze

  def js = @js ||= File.read(JS)
  def html = @html ||= File.read(HTML)
  def tone = @tone ||= File.read(TONE)
  def dilla_data = @dilla_data ||= JSON.parse(File.read(DILLA_DATA))

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

  def test_f_minor_dub_is_labelled_as_an_engine_original
    progression = dilla_data.fetch("progressions").find { |row| row.fetch("id") == "blue_hour" }
    assert_equal "F-minor Dub Study (engine original)", progression.fetch("title")
    assert_includes js, "{n:'F-minor Dub'"
    refute_match(/Blue Hour mirrors|Blue Hour, played as industrial techno/, js)
  end

  def test_rg69_swing_uses_the_same_mpc_curve_as_dilla
    assert_includes js, "function swingOffsetSeconds(stepIdx,sixteenth,intensity,enabled)"
    assert_includes js, "if(!enabled||stepIdx%2===0)return 0;"
    assert_includes js, "const mpcSwing=50+Math.max(0,Math.min(100,Number(intensity)||0))*0.16;"
    assert_includes js, "const position=0.5+((mpcSwing-50)/16)*(2/3-0.5);"
    assert_includes js, "return (position-0.5)*sixteenth*2;"
    trigger = js[/function triggerNotes\(.*?(?=\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    assert_includes trigger, "const swungTime=baseTime+swingOffsetSeconds(stepIdx,sixteenth,aud_.swing,opts.addSwing);"
    assert_includes trigger, "synths.bass.triggerAttackRelease(freq,eighth,swungTime+"
    assert_includes trigger, "synths.keys.triggerAttackRelease(ch,eighth,swungTime+"
    assert_includes trigger, "synths.pads.triggerAttackRelease(pad,half,swungTime+"
    assert_equal 2, js.scan(/addSwing:true/).size,
                 "live playback and WAV export must use the same swung timing"
    refute_includes trigger, "r*(sixteenth/ratch):r*(sixteenth/ratch)"
  end

  def test_randomize_and_style_presets_sync_live_transport_state
    style = js[/chip.addEventListener\('click',\(\)=>\{(.*?)\n\}\);/m, 1] or raise "no style chip handler"
    assert_includes style, "aud_.drive=s.dr[0]+Math.random()*(s.dr[1]-s.dr[0]);"
    assert_includes style, "aud_.tape=s.tm[0]+Math.random()*(s.tm[1]-s.tm[0]);"
    assert_includes style, "syncUIFromState();"
    terminal_style = js[/case'style':\{(.*?)break;\}/m, 1] or raise "no terminal style command"
    assert_includes terminal_style, "aud_.drive=match.dr[0]+Math.random()*(match.dr[1]-match.dr[0]);"
    assert_includes terminal_style, "aud_.tape=match.tm[0]+Math.random()*(match.tm[1]-match.tm[0]);"
    randomize = js[/function randomize\(\).*?(?=\nfunction randomizeFX)/m] or raise "no randomize"
    assert_includes randomize, "syncUIFromState();"
    random_fx = js[/function randomizeFX\(\).*?(?=\nasync function exportWAV)/m] or raise "no randomizeFX"
    assert_includes random_fx, "if(!drumG||!bassG||!keysG||!padsG||!masterG){st_.randomizeFxPending=true;return;}"
    assert_includes random_fx, "applyFX();"
    init = js[/async function initAudio\(.*?(?=\nfunction applyFX)/m] or raise "no initAudio"
    assert_includes init, "if(st_.randomizeFxPending){st_.randomizeFxPending=false;randomizeFX();}else applyFX();"
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

  def test_canvas_dimensions_are_not_measured_in_the_visual_frame_loop
    body = js[/function updateVisuals\(\)(.*?)\n\}/m, 1] or raise "no updateVisuals"
    refute_includes body, "resizeVizCanvas()"
    assert_includes js, "window.addEventListener(\"resize\",resizeVizCanvas"
    assert_includes body, ">=50"
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
    assert_match(/const activationPromise=startToneFromGesture\(\);\s*await startPlayback\(activationPromise\);/, welcome)
    assert_match(/const activationPromise=startToneFromGesture\(\);\s*await startPlayback\(activationPromise\);/, play)
    assert_includes js, "async function initAudio(activationPromise)"
  end

  def test_opaque_origins_do_not_abort_cross_tab_or_theme_storage_startup
    assert_match(/let bc=null;\s*try\{\s*if\("BroadcastChannel"in window\)bc=new BroadcastChannel\("rg69"\);?\s*\}catch\(error\)\{/, js)
    assert_includes js, "function readStorage(key){try{return window.localStorage.getItem(key)}catch(error){return null}}"
    assert_includes js, "function writeStorage(key,value){try{window.localStorage.setItem(key,value);return true}catch(error){return false}}"
    assert_includes js, "function removeStorage(key){try{window.localStorage.removeItem(key);return true}catch(error){return false}}"
    assert_includes js, "writeStorage('rg69_theme',st_.theme)"
    assert_includes js, "const savedTheme=readStorage('rg69_theme')||'dark';"
    assert_equal 3, js.scan(/window\.localStorage\./).size,
                 "every storage access must remain inside one guarded helper"
  end

  def test_tone_default_context_is_lazy_until_first_audio_request
    assert_includes tone, "Destination:()=>w().destination"
    assert_includes tone, "Draw:()=>w().draw"
    assert_includes tone, "Listener:()=>w().listener"
    assert_includes tone, "Master:()=>w().destination"
    assert_includes tone, "Transport:()=>w().transport"
    assert_includes tone, "context:()=>w()"
    refute_includes tone, "const xm=w().transport;const wm=w().destination,bm=w().destination;const Tm=w().listener;const Sm=w().draw;const km=w();"
  end

  def test_rg69_does_not_construct_tone_audio_worklet_reverbs
    refute_match(/Tone\.(?:Freeverb|JCReverb)/, js,
                 "both reverbs instantiate FeedbackCombFilter AudioWorklets, which fail on blob:null origins")
    refute_match(/['"](?:Freeverb|JCReverb)['"]/, js)
    refute_match(/case'(?:Freeverb|JCReverb)'/, js)
  end

  def test_opaque_origin_uses_non_blob_transport_clock
    assert_includes js, 'if(location.origin==="null")context.clockSource="timeout";'
  end

  def test_audio_context_is_created_before_resume_inside_the_user_gesture
    assert_includes js, 'function startToneFromGesture(){const context=Tone.getContext();if(location.origin==="null")context.clockSource="timeout";return Tone.start();}'
    welcome = js[/\$id\('welcome-start'\)\.addEventListener\('click',async\(\)=>\{(.*?)\n\}\);/m, 1]
    play = js[/\$id\('play'\)\.addEventListener\('click',async\(\)=>\{(.*?)\n\}\);/m, 1]
    refute_nil welcome
    refute_nil play
    assert_includes welcome, "const activationPromise=startToneFromGesture();"
    assert_includes play, "const activationPromise=startToneFromGesture();"
    assert_equal 2, js.scan(/if\(st_\.started\)\{Tone\.Transport\.stop\(\);Tone\.Transport\.cancel\(\);\}/).size,
                 "Stop and Panic must not instantiate the Tone context before Play"
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
    assert_includes init, "if(st_.randomizeFxPending){st_.randomizeFxPending=false;randomizeFX();}else applyFX();"
    refute_match(/installDefaultFX\(\);\s*randomizeFX\(\);/, init,
                 "the default chain stays fixed; only an explicit queued action may randomize it")

    # Random effects are created only on explicit randomize, or when a queued
    # pre-audio randomize is finally applied after the graph exists.
    assert_equal 2, js.scan(/randomizeFX\(\);/).size,
                 "randomizeFX may run only for an explicit action or its deferred startup"
  end

  def test_every_default_fx_parameter_is_a_literal_so_boots_are_repeatable
    body = js[/function createDefaultFX\(\)\{(.*?)\n\}/m, 1] or raise "no createDefaultFX"
    refute_includes body, "Math.random", "a default effect parameter must be fixed, not rolled"
    refute_match(/\brnd\(/, body, "a default effect parameter must be fixed, not rolled")

    # The curated chain still uses real effects, not an empty passthrough.
    assert_includes js, "fxRev=new Tone.Reverb(1.5)", "pads still use the shared native reverb send"
    %w[Tone.Chorus Tone.Distortion Tone.FeedbackDelay Tone.StereoWidener].each do |fx|
      assert_includes body, fx, "the fixed chain should include #{fx}"
    end
  end

  def test_rg69_tonejs_adapter_reuses_declared_dilla_kit_voice_and_rig
    profile = dilla_data.fetch("tonejs_profiles").fetch("rg69")
    source = profile.fetch("source")

    assert_equal "kit_break", source.fetch("kit")
    assert_equal "prophet_5", source.fetch("voice")
    assert_equal "basement", source.fetch("rig")
    assert dilla_data.fetch("kits").key?(source.fetch("kit"))
    assert dilla_data.fetch("voices").key?(source.fetch("voice"))
    assert dilla_data.fetch("rigs").key?(source.fetch("rig"))
    %w[kick snare clap hat openhat bass keys pads].each do |lane|
      assert profile.fetch("tone").key?(lane), "Tone.js adapter is missing #{lane}"
    end
    assert_includes js, 'fetch("../data/dilla.json"'
    assert_includes js, "function resolveRG69AudioProfile(data)"
    assert_includes js, "RG69_AUDIO_FALLBACK"
  end

  def test_live_and_offline_use_the_same_profile_driven_instrument_builder
    builder = js[/function createToneInstruments\(\)\{(.*?)\n\}/m, 1] or raise "no shared Tone.js instrument builder"
    init = js[/async function initAudio\(.*?(?=\nfunction applyFX)/m] or raise "no initAudio"
    export = js[/async function exportWAV\(.*?(?=\nlet mediaRecorder)/m] or raise "no exportWAV"

    assert_includes builder, "new Tone.PolySynth(Tone.FMSynth"
    assert_includes builder, "new Tone.PolySynth(Tone.Synth"
    assert_includes init, "const instruments=createToneInstruments();"
    assert_includes export, "const offlineSynths=createToneInstruments();"
    assert_equal 3, js.scan(/createToneInstruments\(\)/).size,
                 "one builder definition and one call in each rendering path"
    refute_match(/new Tone\.PolySynth\(\{\s*maxPolyphony:(?:8|4)/, export,
                 "WAV export must not construct its old, different keys/pads voices"
  end

  def test_rg69_kit_tuning_and_voice_fx_are_shared_by_live_and_wav_paths
    trigger = js[/function triggerNotes\(.*?(?=\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    init = js[/async function initAudio\(.*?(?=\nfunction applyFX)/m] or raise "no initAudio"
    export = js[/async function exportWAV\(.*?(?=\nlet mediaRecorder)/m] or raise "no exportWAV"
    apply = js[/function applyFX\(\)(.*?)\n\}/m, 1] or raise "no applyFX"

    %w[pitch.kick pitch.kickSub pitch.kickBody pitch.snareRing pitch.hat pitch.open].each do |pitch|
      assert_includes trigger, pitch
    end
    assert_includes init, "kitProfile.kick.tone"
    assert_includes init, "kitProfile.snare.tone"
    assert_includes export, "kitProfile.kick.tone"
    assert_includes export, "kitProfile.snare.tone"
    assert_includes init, "keysN.connect(keySat)"
    assert_includes export, "oKeysN.connect(oKeySat)"
    assert_includes init, "padsN.connect(padsFlt)"
    assert_includes export, "oPadsN.connect(oPadsFlt)"
    assert_includes export, "oPadsLFO.connect(oPadsFlt.frequency)"
    assert_includes apply, "profile.rig.delay.feedback"
    assert_includes apply, "profile.rig.reverb.size"
    assert_includes apply, "profile.rig.delay.lowpass"
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
