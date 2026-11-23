# frozen_string_literal: true

require_relative "minitest_helper"
require "json"

# RG-69 is one HTML file, one JS file and one stylesheet, and a person meets it
# through the defaults, not the sliders. Three things have gone wrong before and
# are worth holding still: the panel can drift from the engine (so it shows one
# number while the machine plays another), a boot style can name a pattern key
# the tables do not carry (silence rather than a wrong note), and the master
# chain can drift into randomized saturation that reads as unusable. Boot
# selects a random playable style, so the panel contract is now sync-driven:
# every control is written from engine state at boot and mapped back on input.
#
# This reads the two source files as text and asserts they agree. It never runs
# the page: the sequencer is Tone.js and a browser, and the contract here is the
# boot state the sources declare, which is exactly what drifted.
class TestRg69Defaults < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  JS = File.join(ROOT, "dilla", "rg69", "rg69.js")
  HTML = File.join(ROOT, "dilla", "rg69", "rg69.html")
  TONE = File.join(ROOT, "dilla", "vendor", "tone", "Tone.min.js")
  CSS = File.join(ROOT, "dilla", "rg69", "rg69.css")
  DILLA_DATA = File.join(ROOT, "dilla", "data", "dilla.json")

  # The controls whose markup default must equal the engine's boot default.
  CONTROLS = %w[bpm swing drive tape comp width reverb delay filter wobble vinyl crackle].freeze

  def js = @js ||= File.read(JS)
  def html = @html ||= File.read(HTML)
  def tone = @tone ||= File.read(TONE)
  def css = @css ||= File.read(CSS)
  def dilla_data = @dilla_data ||= JSON.parse(File.read(DILLA_DATA))

  def test_panel_controls_are_driven_by_engine_state_and_mapped_back
    CONTROLS.each do |name|
      assert_operator range_value(name), :>, 0,
                      "rg69.html ##{name} is missing or has no usable range default"
      assert_includes js, "$id('#{name}').value=aud_.#{name};",
                      "rg69.html ##{name} is not written from engine state at boot"
      assert_includes js, "id==='#{name}')aud_.#{name}=v;",
                      "moving ##{name} does not reach the engine state"
    end
    assert_includes js, "syncUIFromState();",
                    "boot must sync the panel from engine state after buildUI"
  end

  def test_boot_patterns_exist_in_the_tables
    filter = js[/const bootStyleCandidates=STYLES\.filter\(style=>\{(.*?)\n\}\);/m, 1] or
             raise "no boot style filter in rg69.js"
    assert_includes filter, "DRUM_PATTERNS[style.d]"
    assert_includes filter, "BASS_PATS[style.b]"
    assert_includes filter, "KEYS_PATS[style.k]"
    assert_includes filter, "PAD_PATS[style.p]"
    assert_includes filter, "some(hit=>hit>0)",
                    "the boot filter must reject silent drum rows"
    assert_includes filter, "bass.some(note=>note)&&keys.some(note=>note&&note!==0)&&pads.some(note=>note&&note!==0)",
                    "the boot filter must reject silent bass, keys and pads rows"
    assert_includes js, "const bootStyle=bootStylePool[Math.floor(Math.random()*bootStylePool.length)];",
                    "boot must pick its style from the filtered, playable pool"
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
    raise "no triggerNotes" unless js.include?("function triggerNotes")
    trigger = js.split("function triggerNotes", 2).last.split("function scheduleLoop", 2).first
    assert_includes trigger, "const swungTime=baseTime+swingOffsetSeconds(stepIdx,sixteenth,aud_.swing,opts.addSwing);"
    assert_includes trigger, "synths.bass.triggerAttackRelease(freq,eighth,bassTime"
    assert_includes trigger, "synths.keys.triggerAttackRelease(ch,eighth,keyTime"
    assert_includes trigger, "synths.pads.triggerAttackRelease(pad,half,noteTime(seq_.p[stepIdx].t)"
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
    chip = js[/const defaultChip=\[.*?\]\.find\(c=>c\.textContent===([^)]+)\);/, 1]
    assert_equal "bootStyle.n", chip,
                 "the highlighted chip must be the boot style's chip"
    assert_includes js, "if(defaultChip)defaultChip.classList.add('active');",
                    "the boot style chip must be selected before the first paint"
  end

  # The point of the retune: the F-minor Dub style is the engine's original
  # industrial-techno reading of the shared harmony, so its grid is
  # four-on-the-floor and its master is driven and tight rather than swung
  # and wet. The boot pool only admits styles whose rows actually play.
  def test_the_f_minor_dub_style_reads_as_industrial_techno
    assert_includes style_names, "F-minor Dub"
    row = js[/\{n:'F-minor Dub',[^\n]+\}/] or raise "no F-minor Dub style row"
    assert_includes row, "sw:[6,12]", "F-minor Dub is on-grid, not swung"
    assert_includes row, "dr:[62,80]", "F-minor Dub wants a driven master"

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
    assert_includes js, "synths.snareRng.triggerAttackRelease(pitch.snareRing,sixteenthDuration,rt,vl*0.5)"
    assert_includes js, "synths.hat.triggerAttackRelease(Math.min(sixteenthDuration*0.5,0.06),rt,vl)"
    assert_includes js, "synths.open.triggerAttackRelease(eighth,rt,vl)"
    assert_includes js, "hat:new Tone.MetalSynth("
    assert_includes js, "open:new Tone.MetalSynth("
    refute_match(/synths\.(?:kickClk|snare|clap|hat|open)\.triggerAttackRelease\(rt,vl/, js)
  end

  def test_keyboard_shortcuts_work_from_welcome_and_range_controls
    # The capture must run to the end of the function body, not to its first
    # inner closing brace: the welcome branch closes on its own line.
    handler = js[/function handleKeys\(e\)\{(.*?)(?=\n\/\/ One gesture)/m, 1] or raise "no handleKeys"
    assert_includes handler, "$id('welcome-start').click()"
    assert_includes handler, "toggleTrackMute"
    refute_includes handler, "if(e.target.tagName==='INPUT'||e.target.tagName==='SELECT')return;"
    assert_includes js, "chip.addEventListener('keydown'"
  end

  def test_welcome_overlay_does_not_swallow_advertised_shortcuts
    handler = js[/function handleKeys\(e\)\{(.*?)(?=\n\/\/ One gesture)/m, 1] or raise "no handleKeys"
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
    init = js[/async function initAudio\([^)]*\).*?(?=\n(?:async )?function )/m] or raise "no initAudio"
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
    assert_includes builder, "maxPolyphony:Math.min(6,t.keys.max_polyphony)"
    assert_includes builder, "maxPolyphony:Math.min(4,t.pads.max_polyphony)"
    assert_includes builder, "oscillator:{type:t.pads.oscillator,count:t.pads.count,spread:t.pads.spread}"
    assert_includes init, "const instruments=createToneInstruments();"
    assert_includes export, "const offlineSynths=createToneInstruments();"
    assert_equal 3, js.scan(/createToneInstruments\(\)/).size,
                 "one builder definition and one call in each rendering path"
    refute_match(/new Tone\.PolySynth\(\{\s*maxPolyphony:(?:8|4)/, export,
                 "WAV export must not construct its old, different keys/pads voices")
  end

  def test_rg69_kit_tuning_and_voice_fx_are_shared_by_live_and_wav_paths
    trigger = js[/function triggerNotes\(.*?(?=\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    init = js[/async function initAudio\(.*?(?=\nfunction applyFX)/m] or raise "no initAudio"
    export = js[/async function exportWAV\(.*?(?=\nlet mediaRecorder)/m] or raise "no exportWAV"
    apply = js[/function applyFX\(\)(.*?)\n\}/m, 1] or raise "no applyFX"

    %w[pitch.kick pitch.kickSub pitch.kickBody pitch.snareRing].each do |pitch|
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
  def test_rg69_stereo_pan_and_vinyl_rig_apply_in_live_and_offline
    panners = js[/function createRG69Panners\(\)\{(.*?)\n\}/m, 1] or raise "no Dilla panner builder"
    init = js[/async function initAudio\(.*?(?=\nfunction applyFX)/m] or raise "no initAudio"
    export = js[/async function exportWAV\(.*?(?=\nlet mediaRecorder)/m] or raise "no exportWAV"
    apply = js[/function applyFX\(\)(.*?)\n\}/m, 1] or raise "no applyFX"

    { "kick" => "k.kick", "snare" => "k.snare", "clap" => "k.perc", "hat" => "k.hat", "open" => "k.openhat" }.each_value do |source|
      assert_includes panners, source
    end
    assert_includes panners, "v.pan"
    assert_includes init, "const livePanners=createRG69Panners();"
    assert_includes export, "const offlinePanners=createRG69Panners();"
    assert_includes apply, "profile.rig.vinyl.level"
    assert_includes apply, "profile.rig.vinyl.crackle"
    assert_includes export, "oVinylNoise.connect(oVinylFlt)"
    assert_includes export, "oCrackleNoise.connect(oCrackleFlt)"
    assert_includes export, "Tone.Time(rg69AudioProfile.effects.delay_time).toSeconds()"
    assert_includes js, "instruments[lane].volume.value=20*Math.log10(level)"
  end
  def test_master_gain_stays_a_gain_and_audio_boot_does_not_block_on_fetch
    init = js[/async function initAudio\(.*?(?=\nfunction applyFX)/m] or raise "no initAudio"
    apply = js[/function applyFX\(\)(.*?)\n\}/m, 1] or raise "no applyFX"
    export = js[/async function exportWAV\(.*?(?=\nlet mediaRecorder)/m] or raise "no exportWAV"

    assert_includes init, "masterG=new Tone.Gain(0.8);"
    assert_includes init, "masterG.connect(fxFlt);"
    assert_includes init, "fxFlt.connect(tapeSat);"
    assert_includes init, "tapeSat.connect(compPar);"
    assert_includes init, "compPar.connect(widener);"
    assert_includes init, "widener.connect(limiter);"
    refute_includes init, "masterG.connect(masterDrive);"
    refute_match(/masterG\s*=\s*new Tone\.Gain\([^)]*\)\.connect/, init)
    assert_includes apply, "if(masterG)masterG.gain.value=mix_.master/100;"
    assert_includes apply, "Math.min(0.75,aud_.tape/100*0.55+(100-aud_.drive)/100*0.25);"
    assert_includes apply, "PARAMS.COMP_RATIO_MAX"
    assert_includes init, "rg69AudioProfileLocked=true;"
    refute_includes init, "await rg69AudioProfileReady"
    refute_includes export, "await rg69AudioProfileReady"
  end


  def test_sub_bass_is_note_gated_not_a_permanent_oscillator
    builder = js[/function createToneInstruments\(\)\{(.*?)\n\}/m, 1] or raise "no Tone.js instrument builder"
    trigger = js[/function triggerNotes\(.*?(?=\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    assert_includes builder, "const bassSub=new Tone.Synth("
    refute_includes builder, "new Tone.Oscillator(t.bass.sub_frequency,t.bass.sub_oscillator).start()"
    assert_includes trigger, "synths.bassSub.triggerAttackRelease("
    refute_includes trigger, "synths.bassSub.frequency.setValueAtTime"
  end

  def test_all_instrument_families_are_scheduled_by_the_same_transport_callback
    scheduler = js[/function scheduleLoop\(time\)\{(.*?)(?=\nlet stepUiByIndex)/m, 1] or raise "no scheduleLoop"
    assert_includes scheduler, "triggerNotes(st_.idx,scheduledTime"
    trigger = js[/function triggerNotes\(.*?(?=\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    %w[synths.kick.triggerAttackRelease synths.bass.triggerAttackRelease synths.keys.triggerAttackRelease synths.pads.triggerAttackRelease].each do |voice|
      assert_includes trigger, voice
    end
  end

  def test_live_and_offline_hats_keep_profile_metal_tone_with_short_envelopes
    builder = js[/function createToneInstruments\(\)\{(.*?)\n\}/m, 1] or raise "no Tone.js instrument builder"
    trigger = js[/function triggerNotes\(.*?(?=\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    init = js[/async function initAudio\(.*?(?=\nfunction applyFX)/m] or raise "no initAudio"
    export = js[/async function exportWAV\(.*?(?=\nlet mediaRecorder)/m] or raise "no exportWAV"
    assert_includes builder, "hat:new Tone.MetalSynth("
    assert_includes builder, "open:new Tone.MetalSynth("
    assert_includes builder, "modulationIndex:t.hat.modulation_index"
    assert_includes builder, "resonance:openResonance"
    assert_includes trigger, "synths.hat.triggerAttackRelease(Math.min(sixteenthDuration*0.5,0.06),rt,vl)"
    assert_includes trigger, "synths.open.triggerAttackRelease(eighth,rt,vl)"
    assert_includes init, "hatFlt=new Tone.Filter(7600,'highpass')"
    assert_includes init, "openFlt=new Tone.Filter(6200,'highpass')"
    assert_includes export, "oHatN.connect(oHatFlt)"
    assert_includes export, "oOpenN.connect(oOpenFlt)"
  end

  def test_closed_hat_gate_finishes_before_the_next_humanized_sixteenth
    trigger = js[/function triggerNotes\\(.*?(?=\\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    assert_includes trigger, "Math.min(sixteenthDuration*0.5,0.06)"
    assert_includes trigger, "synths.hat.triggerAttackRelease(Math.min(sixteenthDuration*0.5,0.06),rt,vl)"
    assert_includes trigger, "synths.open.triggerAttackRelease(eighth,rt,vl)"
    assert_includes trigger, "const noteTime=offsetMs=>Math.max(0,swungTime+(Number(offsetMs)||0)/1000);"
  end

  def test_master_path_avoids_the_old_serial_overprocessing_chain
    init = js[/async function initAudio\(.*?(?=\nfunction applyFX)/m] or raise "no initAudio"
    apply = js[/function applyFX\(\)(.*?)\n\}/m, 1] or raise "no applyFX"
    refute_includes init, "new Tone.Phaser("
    refute_includes init, "new Tone.WaveShaper("
    refute_includes init, "vintageSat=new Tone.Chebyshev(2)"
    refute_includes init, "new Tone.Compressor(-24,3)"
    refute_includes init, "new Tone.Noise('pink').start()"
    assert_includes init, "widener.connect(limiter);"
    assert_includes apply, "PARAMS.COMP_RATIO_MAX"
  end

  def test_rg69_front_panel_is_flat_and_has_a_numbered_step_ruler
    assert_includes html, 'class="machine-header"'
    assert_includes html, 'class="panel-strip panel-strip--inner"'
    assert_includes css, '.machine-header'
    assert_includes css, '.track-ruler'
    assert_includes css, 'border-radius: 0;'
    assert_includes js, "ruler.className='track-ruler'"
    assert_includes js, "tick.textContent=String(i+1).padStart(2,'0')"
  end

  def test_offline_export_clamps_negative_first_step_humanization
    trigger = js[/function triggerNotes\(.*?(?=\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    assert_includes trigger, "const noteTime=offsetMs=>Math.max(0,swungTime+(Number(offsetMs)||0)/1000);"
    assert_includes trigger, "const t=noteTime(seq_[v][stepIdx].t)"
    assert_includes trigger, "const bassTime=noteTime(seq_.b[stepIdx].t)"
    assert_includes trigger, "const keyTime=noteTime(seq_.keys[stepIdx].t)"
    assert_includes trigger, "noteTime(seq_.p[stepIdx].t)"
    refute_includes trigger, "swungTime+seq_.",
                     "offline events must never receive negative AudioParam times at render start"
  end

  def test_wav_export_encodes_native_audio_buffer_as_pcm16
    encoder = js[/function encodeWav16\(audioBuffer\)\{(.*?)\n\}/m, 1] or raise "no PCM WAV encoder"
    assert_includes encoder, "writeText(0,'RIFF');"
    assert_includes encoder, "writeText(8,'WAVE');"
    assert_includes encoder, "view.setUint16(20,1,true);"
    assert_includes encoder, "view.setUint16(34,bytesPerSample*8,true);"
    assert_includes encoder, "audioBuffer.getChannelData(channel)"
    assert_includes encoder, "view.setInt16(offset,sample<0?sample*32768:sample*32767,true);"
    assert_includes js, "const wav=encodeWav16(buf.get());"
    refute_includes js, "Tone.Buffer.toWav"
  end

  def test_visual_step_cursor_waits_for_the_first_transport_tick
    update = js[/function updateStepUI\(\)\{(.*?)\n\}/m, 1] or raise "no step cursor updater"
    assert_includes update, "const next=st_.idx%16;"
    assert_includes update, "if(next<0||next>=stepUiByIndex.length)return;"
    assert_includes update, "stepUiByIndex[next].forEach(el=>el.classList.add('playing'));"
  end

  def test_sequencer_grid_renders_the_current_pattern_on_boot_and_selection
    refresh = js[/function refreshStepGrid\(\)(.*?)\n\}/m, 1] or raise "no state-driven step renderer"
    sync = js[/function syncUIFromState\(\)(.*?)\n\}/m, 1] or raise "no syncUIFromState"
    build = js[/function buildUI\(\)(.*?)(?=\nfunction showCtxMenu\()/m, 1] or raise "no buildUI"

    assert_includes refresh, "const pattern=DRUM_PATTERNS[pat_.d]||{};"
    assert_includes refresh, "step.setAttribute('aria-pressed',velocity>0?'true':'false');"
    assert_includes refresh, "step.dataset.prob"
    assert_includes sync, "refreshStepGrid();"
    assert_includes build, "const updateVelFill=refreshStepGrid;"
    assert_includes build, "refreshStepGrid();updateRootDisplay();highlightActiveChip();"
  end

  def test_transport_and_controls_have_real_hit_areas_and_explicit_states
    assert_includes html, 'class="machine-header"'
    assert_includes html, 'class="panel-strip"'
    assert_includes html, 'class="transport-primary"'
    assert_includes html, 'class="transport-actions"'
    assert_includes html, 'aria-pressed="false" title="Play or pause (Space)"'
    assert_includes js, "$id('play').setAttribute('aria-pressed','true');"
    assert_includes js, "$id('play').setAttribute('aria-pressed','false');"
    assert_includes css, "input[type=\"range\"]{appearance:none;-webkit-appearance:none;width:100%;height:28px;"
    assert_includes css, "::-webkit-slider-thumb{-webkit-appearance:none;width:18px;height:18px;"
    assert_includes css, "#play{min-width:104px;min-height:44px;"
    assert_includes css, ".step{min-height:44px!important}"
  end

  def test_layout_control_uses_two_predictable_density_modes
    assert_includes js, 'const DENSITIES=Object.freeze(["comfortable","compact"]);'
    assert_includes js, "st_.density=st_.density==='comfortable'?'compact':'comfortable';"
    refute_includes js, "Array.from({length:50}"
  end
  private

  def range_value(name)
    match = html.match(/id="#{Regexp.escape(name)}"\s+type="range"[^>]*\bvalue="([\d.]+)"/)
    raise "rg69.html has no range ##{name}" unless match

    match[1].to_f
  end

  def style_names = js.scan(/\{n:'([^']+)'/).flatten

  # The F-minor Dub row is the engine-original boot anchor; other tests read
  # their tables directly. Key defaults to bluehour's four-on-the-floor grid.
  def boot_drum(key = "bluehour")
    block = js[/const DRUM_PATTERNS=\{(.*?)\n\};/m, 1] or raise "no DRUM_PATTERNS table"
    row = block[/'#{Regexp.escape(key)}':tpP\(\{(.*?)\}\)/m, 1] or raise "no drum pattern #{key}"
    row.scan(/(\w+):\[([^\]]*)\]/).to_h do |lane, list|
      [lane, list.split(",").map { |value| value.strip.empty? ? 0.0 : value.to_f }]
    end
  end
end

# Regression coverage for the failure mode and the visible interaction states.
class TestRg69PlaybackRecovery < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  JS = File.join(ROOT, "dilla", "rg69", "rg69.js")
  CSS = File.join(ROOT, "dilla", "rg69", "rg69.css")

  def js = File.read(JS)
  def css = File.read(CSS)

  def test_missing_tone_asset_does_not_leave_the_welcome_gate_covering_the_page
    assert_includes js, 'const trace=$id("trace");'
    assert_includes js, 'welcome.style.display = "none";'
    assert_includes js, 'welcome.setAttribute("aria-hidden", "true");'
    assert_includes js, 'control.disabled = true;'
    assert_includes js, 'status.dataset.state = "audio";'
  end

  def test_play_button_reports_startup_and_exposes_a_retry_on_failure
    assert_includes js, 'playButton.textContent = "Starting…";'
    assert_includes js, 'playButton.textContent = "↻ Retry audio";'
    assert_includes js, 'st(`audio startup failed — ${detail}`);'
    assert_includes js, 'finally {'
  end

  def test_reverb_generation_failure_cannot_block_the_transport
    assert_includes js, 'reverb unavailable; continuing without it:'
    assert_includes js, 'fxRev.wet.value = 0;'
  end

  def test_reverb_failure_stays_bypassed_after_later_fx_updates
    assert_includes js, "let reverbReady = true;"
    assert_includes js, 'reverbReady=typeof fxRev.generate!=="function";'
    assert_includes js, "reverbReady = true;"
    assert_includes js, "reverbReady = false;"
    assert_match(/if\(fxRev\)\{fxRev\.wet\.value=reverbReady\?1:0;/, js)
  end

  def test_touch_controls_have_readable_sizes_and_a_clear_focus_state
    assert_includes css, 'button {'
    assert_includes css, '.machine-header'
    assert_includes css, '.track-ruler'
    assert_includes css, 'border-radius: 0;'
    assert_includes css, 'min-height: 40px;'
    assert_includes css, 'button:focus-visible'
    assert_includes css, '@media (max-width: 640px)'
    assert_includes css, 'grid-template-columns: repeat(2, minmax(0, 1fr));'
  end
end
