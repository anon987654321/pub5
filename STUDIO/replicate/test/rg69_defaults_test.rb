# frozen_string_literal: true

require_relative "minitest_helper"
require "json"

# RG-69 is one HTML file with inline JavaScript and CSS, and a person meets it
# through the defaults, not the sliders. Three things have gone wrong before and
# are worth holding still: the panel can drift from the engine (so it shows one
# number while the machine plays another), a boot style can name a pattern key
# the tables do not carry (silence rather than a wrong note), and the master
# chain can drift into randomized saturation that reads as unusable. Boot
# selects a random playable style, so the panel contract is now sync-driven:
# every control is written from engine state at boot and mapped back on input.
#
# This reads the source as text and asserts they agree. It never runs
# the page: the sequencer is Tone.js and a browser, and the contract here is the
# boot state the sources declare, which is exactly what drifted.
class TestRg69Defaults < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  # The page is one self-contained file: its styles and its application code
  # live inside rg69.html, so the engine and the stylesheet are read from it.
  HTML = File.join(ROOT, "dilla", "rg69", "rg69.html")
  JS = HTML
  CSS = HTML
  TONE = File.join(ROOT, "dilla", "vendor", "tone", "Tone.min.js")
  DILLA_DATA = File.join(ROOT, "dilla", "data", "dilla.json")

  # The controls whose markup default must equal the engine's boot default.
  CONTROLS = %w[bpm pocket swing drive tape comp width reverb delay filter wobble vinyl crackle].freeze

  def js = @js ||= File.read(JS).sub(/<script id="tone-vendor">.*?<\/script>/m, "")
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

  def test_industrial_techno_remains_a_first_class_style
    %w[Industrial].concat(["Hard Techno", "HATE Style"]).each do |name|
      assert_includes style_names, name
    end
    %w[hate-pummel hate-grind].each do |pattern|
      kick = boot_drum(pattern).fetch("k")
      [0, 4, 8, 12].each { |step| assert_equal 1, kick[step] }
    end
    assert_includes js, "const bootStylePool=industrialBoot.length?industrialBoot:"
    assert_includes js, "aud_.pocket=industrial?12:68;"
  end

  def test_f_minor_dub_is_labelled_as_an_engine_original
    progression = dilla_data.fetch("progressions").find { |row| row.fetch("id") == "blue_hour" }
    assert_equal "F-minor Dub Study (engine original)", progression.fetch("title")
    assert_includes js, "{n:'F-minor Dub'"
    refute_match(/Blue Hour mirrors|Blue Hour, played as industrial techno/, js)
  end

  def test_local_profile_and_clock_do_not_require_a_worker_or_fetch
    assert_includes js, "kick:Tone.mtof(24+Number(kit.kick.tune))"
    assert_includes js, 'const httpPage=location.protocol==="http:"||location.protocol==="https:";'
    assert_match(/const rg69AudioProfileReady=!httpPage\|\|location\.origin==="null"\s*\?Promise\.resolve\(\)/, js)
    assert_includes js, 'if((!httpPage||location.origin==="null")&&!fileClockConfigured)'
    assert_includes js, 'Tone.setContext(new Tone.Context({context:native,clockSource:"timeout",lookAhead:.15,updateInterval:.025}));'
  end

  def test_ratchets_fit_before_the_next_humanized_step
    assert_includes js, "const nextStep=(stepIdx+1)%(opts.stepCount||16);"
    assert_includes js, "const ratchetSpan=Math.min(sixteenth,Math.max(0,nextTime-t));"
    assert_includes js, "const rt=t+r*(ratchetSpan/ratch);"
    assert_includes js, "stepCount:st_.stepCount"
    assert_includes js, "const limit=Math.min(.025,sixteenth/4);"
  end

  def test_rg69_swing_uses_the_same_mpc_curve_as_dilla
    assert_includes js, "function swingOffsetSeconds(stepIdx,sixteenth,intensity,enabled)"
    assert_includes js, "if(!enabled||stepIdx%2===0)return 0;"
    assert_includes js, "const mpcSwing=50+Math.max(0,Math.min(100,Number(intensity)||0))*0.16;"
    assert_includes js, "const position=0.5+((mpcSwing-50)/16)*(2/3-0.5);"
    assert_includes js, "return (position-0.5)*sixteenth*2;"
    assert_includes js, "aud.swing*pocket*(DRUM_LANES.includes(lane)?1:.65)"
    assert_includes js, "noteTime(\"b\")"
    assert_includes js, "noteTime(\"keys\")"
    assert_includes js, "noteTime(\"p\")"
    assert_includes js, "function compileStep("
    assert_includes js, "function playStep("
  end

  def test_randomize_and_style_presets_sync_live_transport_state
    assert_includes js, "function randomize(){"
    assert_includes js, "sessionSeed=newSeed();"
    assert_includes js, "randomAt(sessionSeed,i,t,5)"
    assert_includes js, "syncUIFromState();saveSession();"
    assert_includes js, "function randomizeFX(){"
    assert_includes js, "fxSeed=newSeed();"
    assert_includes js, "if(laneRoutes)refreshLaneFX();else st_.randomizeFxPending=true;"
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
  def test_html_loads_tone_before_the_inlined_engine
    embedded = html[/<script id="tone-vendor">\n\/\*.*?\*\/\n(.*?)\n<\/script>/m, 1]
    assert_equal tone, embedded, "embedded Tone.js must match the pinned vendor exactly"
    assert_includes html, File.read(File.join(File.dirname(TONE), "LICENSE.md")).strip
    refute_match(/<script[^>]*\bsrc=/i, html)
    tone_at = html.index('<script id="tone-vendor">')
    engine_at = html.index("<script>\n")
    refute_nil engine_at
    assert_operator tone_at, :<, engine_at
    assert_operator engine_at, :>, html.index('id="main-content"')
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
    assert_includes panic, "pauseClock();"
  end

  def test_percussion_synthesizers_receive_their_correct_tonejs_arguments
    assert_includes js, "synths.kickClk.triggerAttackRelease(hitGate(thirtySecond),rt,vl*0.3)"
    assert_includes js, "synths.snare.triggerAttackRelease(hitGate(eighth),rt,vl)"
    assert_includes js, "synths.clap.triggerAttackRelease(hitGate(sixteenthDuration),rt,vl)"
    assert_includes js, "synths.snareRng.triggerAttackRelease(pitch.snareRing*pitchShift,hitGate(sixteenthDuration),rt,vl*0.5)"
    assert_includes js, "synths.hat.triggerAttackRelease(pitch.hat*pitchShift,hitGate(Math.min(sixteenthDuration*.5,.06)),rt,vl)"
    assert_includes js, "synths.open.triggerAttackRelease(pitch.open*pitchShift,hitGate(eighth),rt,vl)"
    assert_includes js, "function createDrumBank(ctx,profile,connect)"
    assert_includes js, "...createDrumBank(Tone.getContext().rawContext,p,Tone.connect)"
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
    assert_includes js, 'Tone.setContext(new Tone.Context({context:native,clockSource:"timeout",lookAhead:.15,updateInterval:.025}));'
  end

  def test_audio_context_is_created_before_resume_inside_the_user_gesture
    assert_includes js, 'function startToneFromGesture(){'
    welcome = js[/\$id\('welcome-start'\)\.addEventListener\('click',async\(\)=>\{(.*?)\n\}\);/m, 1]
    play = js[/\$id\('play'\)\.addEventListener\('click',async\(\)=>\{(.*?)\n\}\);/m, 1]
    refute_nil welcome
    refute_nil play
    assert_includes welcome, "const activationPromise=startToneFromGesture();"
    assert_includes play, "const activationPromise=startToneFromGesture();"
    refute_includes js, "Tone.Transport.scheduleRepeat"
    assert_includes js, "startClock();"
    assert_includes js, "pauseClock();"
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
    assert_includes js, "function createRandomFX(seed,bpm)"
    assert_includes js, "const num=1+Math.floor(random()*2);"
    assert_includes js, "const wet=.15+random()*.35;"
    assert_includes js, "function refreshLaneFX("
  end

  def test_boot_installs_a_fixed_chain_and_never_randomizes
    assert_includes js, "const effects=seed==null?createDefaultFX(aud.bpm):createRandomFX(seed,aud.bpm);"
    assert_includes js, "const graph=liveGraph=createAudioGraph(aud_,mix_,fxSeed);"
    assert_match(/fxSeed\s*=\s*null/, js)
  end

  def test_every_default_fx_parameter_is_a_literal_so_boots_are_repeatable
    body = js[/function createDefaultFX\(bpm\)\{(.*?)\n\}/m, 1] or raise "no createDefaultFX"
    refute_includes body, "Math.random"
    refute_match(/\brnd\(/, body)
    assert_includes js, "const rev=new Tone.Reverb(1+profileReverbDecay());"
    %w[Tone.Chorus Tone.Distortion Tone.FeedbackDelay Tone.StereoWidener].each do |fx|
      assert_includes body, fx
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
    assert_includes js, "new Tone.PolySynth({voice:Tone.FMSynth"
    assert_includes js, "maxPolyphony:Math.max(16,t.keys.max_polyphony)"
    assert_includes js, "maxPolyphony:Math.max(24,t.pads.max_polyphony)"
    assert_includes js, "const instruments=createToneInstruments();"
    assert_includes js, "const graph=liveGraph=createAudioGraph(aud_,mix_,fxSeed);"
    assert_includes js, "const graph=createAudioGraph(aud_,mix_,take.fxSeed,{offline:true,duration:len+leadIn});"
    assert_equal 2, js.scan(/createToneInstruments\(\)/).size
  end

  def test_rg69_kit_tuning_and_voice_fx_are_shared_by_live_and_wav_paths
    assert_includes js, "pitch.kick"
    assert_includes js, "pitch.kickSub"
    assert_includes js, "pitch.kickBody"
    assert_includes js, "pitch.snareRing"
    assert_includes js, "kitProfile.kick.tone"
    assert_includes js, "kitProfile.snare.tone"
    assert_includes js, "keysN.connect(keySat)"
    assert_includes js, "padsN.connect(padsFlt)"
    assert_includes js, "padsLFO.connect(padsFlt.frequency)"
    assert_includes js, "profile.rig.delay.feedback"
    assert_includes js, "profile.rig.delay.lowpass"
  end
  def test_rg69_stereo_pan_and_vinyl_rig_apply_in_live_and_offline
    assert_includes js, "const panners=createRG69Panners();"
    assert_includes js, "profile.rig.vinyl.level"
    assert_includes js, "profile.rig.vinyl.crackle"
    assert_includes js, "vinylFlt.connect(masterG)"
    assert_includes js, "crackleFlt.connect(masterG)"
    assert_includes js, "out.gain.value=Math.max(.001,Number(level)||1)"
  end
  def test_master_gain_stays_a_gain_and_audio_boot_does_not_block_on_fetch
    assert_includes js, "const masterG=new Tone.Gain(mix.master/100);"
    assert_includes js, "masterG.connect(flt);"
    assert_includes js, "flt.connect(tape);"
    assert_includes js, "tape.connect(comp);"
    assert_includes js, "comp.connect(widener);"
    assert_includes js, "widener.connect(limiter);"
    assert_includes js, "dryMaster.connect(outputGate);"
    assert_includes js, "wetMaster.connect(outputGate);"
    assert_includes js, "outputGate.connect(finalLimiter);finalLimiter.connect(ctx.destination);"
    assert_includes js, "if(masterG)smooth(masterG.gain,mix_.master/100);"
    assert_includes js, "if(tapeSat)smooth(tapeSat.wet,aud_.tape/100*.65);"
    assert_includes js, "if(liveGraph?.drumDrive)smooth(liveGraph.drumDrive.wet,aud_.drive/100*.75);"
    assert_includes js, "drumDrive.connect(drumG);"
    assert_includes js, "rg69AudioProfileLocked=true;"
    refute_includes js, "await rg69AudioProfileReady"
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
    assert_includes scheduler, "playStep(st_.idx,scheduledTime"
    trigger = js[/function triggerNotes\(.*?(?=\nfunction scheduleLoop)/m] or raise "no triggerNotes"
    %w[synths.kick.triggerAttackRelease synths.bass.triggerAttackRelease synths.keys.triggerAttackRelease synths.pads.triggerAttackRelease].each do |voice|
      assert_includes trigger, voice
    end
  end

  def test_live_and_offline_hats_keep_profile_metal_tone_with_short_envelopes
    assert_includes js, "function createDrumBank(ctx,profile,connect)"
    assert_includes js, "...createDrumBank(Tone.getContext().rawContext,p,Tone.connect)"
    assert_includes js, "const metal=[1,1.483,1.932,2.546,2.63,3.897];"
    assert_includes js, "hat:[k.hat.decay,t.hat.attack,n.hat"
    assert_includes js, "open:[k.openhat.decay,t.openhat.attack,n.open"
    assert_includes js, "hatFlt=new Tone.Filter(5500,'highpass')"
    assert_includes js, "openFlt=new Tone.Filter(4200,'highpass')"
    assert_includes js, "hatN.connect(hatFlt)"
    assert_includes js, "openN.connect(openFlt)"
    assert_includes js, "hitGate(Math.min(sixteenthDuration*.5,.06))"
  end

  def test_console_bridge_and_audio_probe
    assert_includes html, '<script id="console-bridge">'
    assert_operator html.index('<script id="console-bridge">'), :<, html.index('<script id="tone-vendor">')
    assert_includes js, "window.rg69ConsoleSink=mirrorConsole;"
    assert_includes html, 'id="copy-log"'
    assert_includes html, 'id="audio-test"'
    assert_includes js, "gain.connect(ctx.destination);"
    assert_includes js, "logAudioState();"
  end

  def test_percussion_uses_independent_one_shots_and_permanent_dry_routes
    assert_includes js, "const source=ctx.createBufferSource()"
    assert_includes js, "source.start(at);source.stop(end);"
    assert_includes js, "drumClean.connect(drumG);"
    assert_includes js, "drumG.connect(masterG);drumG.connect(drumFXSend);"
    assert_includes js, "bassG.connect(masterG);bassG.connect(bassFXSend);"
    assert_includes js, 'id="reset-mix"'
    refute_includes js, "oneShotMetal("
  end

  def test_closed_hat_gate_finishes_before_the_next_humanized_sixteenth
    assert_includes js, "hitGate(Math.min(sixteenthDuration*.5,.06))"
    assert_includes js, "ratchetSpan/ratch*.9"
    assert_includes js, "const noteTime=lane=>Math.max(0,baseTime+swing(lane,stepIdx)+microtimingSeconds(offset(lane),sixteenth));"
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
    assert_includes js, "const noteTime=lane=>Math.max(0,baseTime+swing(lane,stepIdx)+microtimingSeconds(offset(lane),sixteenth));"
    assert_includes js, "const t=noteTime(v);"
    assert_includes js, "noteTime(\"b\")"
    assert_includes js, "noteTime(\"keys\")"
    assert_includes js, "noteTime(\"p\")"
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
    assert_includes js, "const next=st_.visualIdx>=0&&Math.floor(st_.visualIdx/16)===st_.bank?st_.visualIdx%16:-1;"
    assert_includes js, "if(next>=0&&next<stepUiByIndex.length)stepUiByIndex[next].forEach(el=>el.classList.add('playing'));"
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
    assert_includes html, 'class="panel-strip panel-strip--inner"'
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
  JS = File.join(ROOT, "dilla", "rg69", "rg69.html")
  CSS = JS

  def js = File.read(JS).sub(/<script id="tone-vendor">.*?<\/script>/m, "")
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
    assert_includes js, "reverb unavailable; continuing without it:"
    assert_includes js, "revSend.gain.value=0;"
    assert_includes js, "return false;"
  end

  def test_reverb_failure_stays_bypassed_after_later_fx_updates
    assert_includes js, "graph.ready.then(ok=>{reverbReady=ok;applyFX();}).catch("
    assert_includes js, "if(fxRev)fxRev.wet.value=reverbReady?1:0;"
    assert_includes js, "if(!reverbReady&&revSend)revSend.gain.value=0;"
  end

  def test_touch_controls_have_readable_sizes_and_a_clear_focus_state
    assert_includes css, 'button {'
    assert_includes css, '.machine-header'
    assert_includes css, '.track-ruler'
    assert_includes css, 'border-radius: 0;'
    assert_includes css, 'min-height: 40px;'
    assert_includes css, 'button:focus-visible'
    assert_match(/@media\s*\(max-width:\s*640px\)/, css)
    assert_includes css, 'grid-template-columns: repeat(2, minmax(0, 1fr));'
  end
end
