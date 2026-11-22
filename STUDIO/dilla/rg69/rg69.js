"use strict";

// Global error handlers for runtime failure reporting
window.addEventListener('unhandledrejection', (event) => {
  console.error('Unhandled promise rejection:', event.reason);
  // Don't prevent default to allow browser's error reporting
});

window.addEventListener('error', (event) => {
  console.error('Global error:', event.error || event.message);
});

if(!window.Tone){
  const warning=document.createElement("p");
  warning.className="engine-error";
  warning.setAttribute("role","alert");
  warning.textContent="The RG-69 audio engine (Tone.js 14.8.49) did not load. Check your connection and reload.";
  document.body.prepend(warning);
  throw new Error("RG-69 audio engine unavailable");
}

const INSTANCE_KEY="rg69_inst",INSTANCE_TTL=8e3,selfId=`${Date.now()}-${Math.random().toString(16).slice(2)}`;
let bc=null;
try{
if("BroadcastChannel"in window)bc=new BroadcastChannel("rg69");
}catch(error){
console.warn("RG-69 cross-tab coordination unavailable:",error);
}
function readStorage(key){try{return window.localStorage.getItem(key)}catch(error){return null}}
function writeStorage(key,value){try{window.localStorage.setItem(key,value);return true}catch(error){return false}}
function removeStorage(key){try{window.localStorage.removeItem(key);return true}catch(error){return false}}
const $id=s=>document.getElementById(s),DP=s=>$id(s).parentElement;
const vizCanvas=$id("viz");
let vizContext=null;
let vizColors={background:"#0c0c0c",accent:"#c8902e"};
function refreshVizColors(){
  const style=getComputedStyle(document.documentElement);
  vizColors.background=style.getPropertyValue("--bg").trim()||"#0c0c0c";
  vizColors.accent=style.getPropertyValue("--acc").trim()||"#c8902e";
}
function resizeVizCanvas(){
  if(!vizCanvas)return;
  const width=Math.max(1,vizCanvas.clientWidth|0);
  const height=Math.max(1,vizCanvas.clientHeight|0);
  if(vizCanvas.width!==width)vizCanvas.width=width;
  if(vizCanvas.height!==height)vizCanvas.height=height;
  if(!vizContext)vizContext=vizCanvas.getContext("2d");
}
window.addEventListener("resize",resizeVizCanvas,{passive:true});
const welcomeStart=$id("welcome-start");
if(welcomeStart){
  welcomeStart.focus({preventScroll:true});
  $id("welcome").addEventListener("keydown",event=>{
    if(event.key==="Tab"){
      event.preventDefault();
      welcomeStart.focus({preventScroll:true});
    }
  });
}
function dismissWelcome(){
  $id("welcome").style.display="none";
  $id("play").focus({preventScroll:true});
}
const log=(message,level="i")=>{
  const entry=document.createElement("span");
  entry.classList.add("trace-line");
  if(level==="e")entry.classList.add("trace-line--error");
  else if(level==="k")entry.classList.add("trace-line--success");
  else if(level==="c")entry.classList.add("trace-line--command");
  const time=document.createElement("b");
  time.className="trace-time";
  time.textContent=new Date().toISOString().slice(11,19);
  entry.append(time,document.createTextNode(` ${String(message)}`));
  trace.appendChild(entry);
  while(trace.children.length>PARAMS.TRACE_MAX_LINES)trace.removeChild(trace.firstChild);
  trace.scrollTop=trace.scrollHeight;
};
const st=s=>$id("status").textContent=`status: ${s}`;
const tp=(a,t)=>Array.isArray(a)?a:Array(t||16).fill(a);
const tpP=object=>Object.fromEntries(Object.entries(object).map(([key,value])=>[key,tp(value)]));
const debounce=(f,d)=>{let t;return(...a)=>{clearTimeout(t);t=setTimeout(()=>f(...a),d)}};
const rnd=(n,x)=>n+Math.random()*(x-n);
const rndInt=(n,x)=>Math.floor(rnd(n,x+1));
const PARAMS={
  REVERB_DECAY_MAX:4,
  REVERB_SEND:0.35,
  DELAY_SEND:0.28,
  DELAY_FB_MAX:0.55,
  FILTER_MAX_HZ:15950,
  FILTER_MIN_HZ:50,
  COMP_RATIO_MAX:7,
  VU_BARS:10,
  VU_DECAY:0.85,
  TRACE_MAX_LINES:90,
  WOBB_FREQ_MAX:0.15,
  WOBB_DEPTH_MAX:0.04,
  DRIFT_FREQ_MAX:0.15,
  KEYS_LP_HZ:5000,
  PADS_LP_HZ:3500,
  INSTANCE_TTL_MS:8000,
};

const RG69_AUDIO_FALLBACK={
name:"RG-69 embedded sound fallback",
tone:{
kick:{pitch_decay:.05,octaves:6,oscillator:"sine",attack:.001,release:.1,click_attack:.001,click_decay:.02,body_oscillator:"triangle",body_attack:.001,body_decay:.08,click_filter_base_hz:600,click_filter_tone_span_hz:1200,click_filter_q:5},
snare:{noise:"white",attack:.001,ring_oscillator:"triangle",ring_attack:.001,ring_decay:.15,ring_frequency:400,ring_filter_base_hz:100,ring_filter_tone_span_hz:450,ring_filter_q:3},
clap:{noise:"pink",attack:.001},
hat:{frequency:200,attack:.001,release:.01,harmonicity:5.1,modulation_index:32,resonance_base_hz:500,resonance_tone_span_hz:5000,octaves:1.5},
openhat:{frequency:200,attack:.001,release:.2,harmonicity:5.1,modulation_index:32,resonance_base_hz:500,resonance_tone_span_hz:5000,octaves:1.5},
bass:{oscillator:"sawtooth",attack:.01,decay:.1,sustain:.5,release:.1,sub_frequency:40,sub_oscillator:"sine",sub_volume_db:-12},
keys:{max_polyphony:16,harmonicity:7,modulation_index:2.5,brightness_reference:.58,oscillator:"sine",attack:.005,decay:.1,sustain:.3,release:.1,modulation_oscillator:"square",mod_attack:.01,mod_decay:.2,mod_sustain:.2,mod_release:.3,filter_base_hz:1200,filter_brightness_span_hz:3800,chorus_frequency:2.5,chorus_delay_time:.3,chorus_depth:.3,tremolo_frequency:3.2,tremolo_depth:.2,tremolo_wet:.25,tremolo_spread:90,drive_amount:.08,drive_wet:.15,texture_amount:.18,texture_wet:.6},
pads:{max_polyphony:16,oscillator:"fatsawtooth",count:3,spread:25,attack:2.2,decay:3.5,sustain:.75,release:4.8,filter_base_hz:600,filter_brightness_span_hz:400,lowpass_hz:3500,saturation_order:2,saturation_wet:.2}
},
kit:{kick:{tune:0,decay:.4,tone:.5},sub:{tune:-12,decay:.5},snare:{tune:0,decay:.2,tone:.6},hat:{tune:0,decay:.1,tone:.6},openhat:{decay:.3},perc:{decay:.15}},
voice:{brightness:.58,level:1},
rig:{delay:{feedback:.1,lowpass:16000,throw_chords:.28},reverb:{size:1,level_chords:.35},wobble:{rate_hz:.15},vinyl:{level:.1,crackle:.075}},
effects:{delay_feedback_range:.55,reverb_decay_scale:4,wobble_frequency_cap_hz:.15}
};
function finalizeRG69AudioProfile(profile){
const kit=profile.kit,tone=profile.tone;
return Object.assign({},profile,{notes:Object.freeze({
kick:Tone.Frequency("C1").transpose(kit.kick.tune).toFrequency(),
kickSub:Tone.Frequency("C1").transpose(kit.sub.tune).toFrequency(),
kickBody:Tone.Frequency("C2").transpose(kit.kick.tune).toFrequency(),
snareRing:Tone.Frequency("E4").transpose(kit.snare.tune).toFrequency(),
hat:Tone.Frequency(tone.hat.frequency).transpose(kit.hat.tune).toFrequency(),
open:Tone.Frequency(tone.openhat.frequency).transpose(kit.hat.tune).toFrequency()
})});
}
function resolveRG69AudioProfile(data){
const config=data&&data.tonejs_profiles&&data.tonejs_profiles.rg69;
if(!config||!config.source)throw new Error("Dilla tonejs_profiles.rg69 is missing");
const kit=data.kits&&data.kits[config.source.kit],voice=data.voices&&data.voices[config.source.voice],rig=data.rigs&&data.rigs[config.source.rig];
if(!kit||!voice||!rig)throw new Error("RG-69 profile references an unknown Dilla kit, voice or rig");
for(const lane of ["kick","sub","snare","hat","openhat","perc"])if(!kit[lane])throw new Error("RG-69 source kit is missing "+lane);
if(!voice.brightness||!rig.delay||!rig.reverb||!rig.wobble)throw new Error("RG-69 source voice or rig is incomplete");
return finalizeRG69AudioProfile({name:config.name,tone:config.tone,kit,voice,rig,effects:config.effects,source:config.source});
}
let rg69AudioProfile=finalizeRG69AudioProfile(RG69_AUDIO_FALLBACK);
const rg69AudioProfileReady=fetch("../data/dilla.json",{cache:"force-cache"})
.then(response=>{if(!response.ok)throw new Error("Dilla catalogue request failed: "+response.status);return response.json();})
.then(data=>{rg69AudioProfile=resolveRG69AudioProfile(data);log("shared Dilla sound profile: "+rg69AudioProfile.name,"k");return rg69AudioProfile;})
.catch(error=>{console.warn("RG-69 shared Dilla sound profile unavailable; embedded fallback retained:",error);log("shared Dilla sound profile unavailable; using embedded RG-69 patch","w");return rg69AudioProfile;});
function createToneInstruments(){
const p=rg69AudioProfile,t=p.tone,k=p.kit,v=p.voice;
const hatResonance=t.hat.resonance_base_hz+k.hat.tone*t.hat.resonance_tone_span_hz;
const openResonance=t.openhat.resonance_base_hz+k.hat.tone*t.openhat.resonance_tone_span_hz;
const keysModulation=t.keys.modulation_index*(v.brightness/t.keys.brightness_reference);
const bassSub=new Tone.Oscillator(t.bass.sub_frequency,t.bass.sub_oscillator).start();bassSub.volume.value=t.bass.sub_volume_db;
return{
kick:new Tone.MembraneSynth({pitchDecay:t.kick.pitch_decay,octaves:t.kick.octaves,oscillator:{type:t.kick.oscillator},envelope:{attack:t.kick.attack,decay:k.kick.decay,sustain:0,release:t.kick.release}}),
kickSub:new Tone.Synth({oscillator:{type:"sine"},envelope:{attack:.001,decay:k.sub.decay,sustain:0,release:.1}}),
kickClk:new Tone.NoiseSynth({noise:{type:"white"},envelope:{attack:t.kick.click_attack,decay:t.kick.click_decay,sustain:0}}),
kickBody:new Tone.Synth({oscillator:{type:t.kick.body_oscillator},envelope:{attack:t.kick.body_attack,decay:t.kick.body_decay,sustain:0}}),
snare:new Tone.NoiseSynth({noise:{type:t.snare.noise},envelope:{attack:t.snare.attack,decay:k.snare.decay,sustain:0}}),
snareRing:new Tone.Synth({oscillator:{type:t.snare.ring_oscillator},envelope:{attack:t.snare.ring_attack,decay:t.snare.ring_decay,sustain:0}}),
clap:new Tone.NoiseSynth({noise:{type:t.clap.noise},envelope:{attack:t.clap.attack,decay:k.perc.decay,sustain:0}}),
hat:new Tone.MetalSynth({frequency:p.notes.hat,envelope:{attack:t.hat.attack,decay:k.hat.decay,release:t.hat.release},harmonicity:t.hat.harmonicity,modulationIndex:t.hat.modulation_index,resonance:hatResonance,octaves:t.hat.octaves}),
open:new Tone.MetalSynth({frequency:p.notes.open,envelope:{attack:t.openhat.attack,decay:k.openhat.decay,release:t.openhat.release},harmonicity:t.openhat.harmonicity,modulationIndex:t.openhat.modulation_index,resonance:openResonance,octaves:t.openhat.octaves}),
bass:new Tone.MonoSynth({oscillator:{type:t.bass.oscillator},envelope:{attack:t.bass.attack,decay:t.bass.decay,sustain:t.bass.sustain,release:t.bass.release}}),
bassSub,
keys:new Tone.PolySynth(Tone.FMSynth,{maxPolyphony:t.keys.max_polyphony,harmonicity:t.keys.harmonicity,modulationIndex:keysModulation,oscillator:{type:t.keys.oscillator},envelope:{attack:t.keys.attack,decay:t.keys.decay,sustain:t.keys.sustain,release:t.keys.release},modulation:{type:t.keys.modulation_oscillator},modulationEnvelope:{attack:t.keys.mod_attack,decay:t.keys.mod_decay,sustain:t.keys.mod_sustain,release:t.keys.mod_release}}),
pads:new Tone.PolySynth(Tone.Synth,{maxPolyphony:t.pads.max_polyphony,oscillator:{type:t.pads.oscillator,count:t.pads.count,spread:t.pads.spread},envelope:{attack:t.pads.attack,decay:t.pads.decay,sustain:t.pads.sustain,release:t.pads.release}})
};
}

const DRUM_PATTERNS={
'eth-mulatu':tpP({k:[1,0,0,.5,0,0,.7,0,0,1,0,0,.5,0,.6,0],s:[0,0,0,0,.8,0,0,.3,0,0,0,0,.9,0,0,.3],c:[0,0,0,0,0,0,0,0,0,0,.4,0,0,0,0,0],h:[.6,.3,.5,.3,.6,.3,.5,.3,.6,.3,.5,.3,.6,.3,.5,.3],o:[0,0,0,0,0,0,0,.4,0,0,0,0,0,0,0,.3]}),
'eth-funk':tpP({k:[1,0,0,0,.6,0,1,0,0,.5,0,0,1,0,.5,0],s:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,.4],c:[0,0,.3,0,0,0,.3,0,0,0,.3,0,0,0,.3,0],h:[.7,.5,.7,.5,.7,.5,.7,.5,.7,.5,.7,.5,.7,.5,.7,.5],o:[0,0,0,0,0,0,0,.5,0,0,0,0,0,0,0,.5]}),
'reg-onedrop':tpP({k:[0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],s:[0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[0,.5,0,.5,0,.5,0,.5,0,.5,0,.5,0,.5,0,.5],o:[0,0,0,0,0,0,0,.3,0,0,0,0,0,0,0,.3]}),
'reg-steppers':tpP({k:[1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],s:[0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[0,.4,0,.4,0,.4,0,.4,0,.4,0,.4,0,.4,0,.4],o:[0,0,0,0,0,0,0,.3,0,0,0,0,0,0,0,.3]}),
'reg-dub':tpP({k:[0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0],s:[0,0,0,0,0,0,0,0,.6,0,0,0,0,0,0,0],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[0,.3,0,0,0,.2,0,0,0,.3,0,0,0,.2,0,0],o:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}),
'hate-pummel':tpP({k:[1,0,.7,0,1,0,.8,0,1,0,.7,0,1,0,.9,0],s:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[1,.8,1,.7,1,.8,1,.7,1,.8,1,.7,1,.8,1,.7],o:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}),
'hate-grind':tpP({k:[1,0,0,.5,1,0,0,.6,1,0,0,.5,1,0,0,.7],s:[0,0,0,0,.9,0,0,.3,0,0,0,0,.9,0,0,.4],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[.9,.8,.9,.7,.9,.8,.9,.7,.9,.8,.9,.7,.9,.8,.9,.7],o:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}),
'afro-tony':tpP({k:[1,0,0,.5,0,0,1,0,0,.7,0,0,1,0,.4,0],s:[0,0,0,0,0,0,0,0,0,0,0,0,.9,0,0,0],c:[0,0,.4,0,0,0,0,0,.4,0,0,0,0,0,.4,0],h:[.7,.4,.6,.4,.7,.4,.6,.4,.7,.4,.6,.4,.7,.4,.6,.4],o:[0,0,0,0,0,0,0,.5,0,0,0,0,0,0,0,.5]}),
'afro-fela':tpP({k:[1,0,0,0,1,0,0,0,1,0,0,0,1,0,.5,0],s:[0,0,0,0,.8,0,0,.3,0,0,0,0,.8,0,0,.3],c:[0,0,.3,0,0,0,.3,0,0,0,.3,0,0,0,.3,0],h:[.8,.5,.8,.5,.8,.5,.8,.5,.8,.5,.8,.5,.8,.5,.8,.5],o:[0,0,0,0,0,0,0,.4,0,0,0,0,0,0,0,.4]}),
'bossa-clave':tpP({k:[1,0,0,.4,0,0,.6,0,0,0,1,0,.4,0,0,0],s:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[.3,.3,.3,.3,.3,.3,.3,.3,.3,.3,.3,.3,.3,.3,.3,.3],o:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}),
'bossa-samba':tpP({k:[1,0,.4,0,0,.4,0,0,1,0,.4,0,0,.4,0,0],s:[0,0,0,0,.5,0,0,0,0,0,0,0,.5,0,0,.3],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[.4,.2,.4,.2,.4,.2,.4,.2,.4,.2,.4,.2,.4,.2,.4,.2],o:[0,0,0,0,0,0,0,.3,0,0,0,0,0,0,0,.3]}),
'trap-basic':tpP({k:[1,0,0,0,0,0,0,0,1,0,.5,.5,0,0,0,0],s:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],c:[0,0,0,0,.6,0,0,0,0,0,0,0,.6,0,0,0],h:[1,.5,1,.5,1,.5,1,.5,1,.5,1,.5,1,.5,1,.5],o:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}),
'drill-dark':tpP({k:[1,0,0,0,0,0,.7,0,0,0,1,0,0,0,.5,0],s:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,.4],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[.8,.5,.8,.3,.8,.5,.8,.3,.8,.5,.8,.3,.8,.5,.8,.3],o:[0,0,0,0,0,0,0,.4,0,0,0,0,0,0,0,.4]}),
'broken-classic':tpP({k:[1,0,0,0,0,0,.7,0,0,0,1,0,0,.5,0,0],s:[0,0,0,0,1,0,0,0,0,0,0,0,.8,0,0,.4],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[.5,.3,.5,.3,.5,.3,.5,.3,.5,.3,.5,.3,.5,.3,.5,.3],o:[0,0,0,0,0,0,0,.3,0,0,0,0,0,0,0,.4]}),
'broken-westldn':tpP({k:[1,0,0,.4,0,0,0,.6,0,0,1,0,0,0,.5,0],s:[0,0,0,0,.9,0,0,0,0,0,0,.4,.8,0,0,0],c:[0,0,.3,0,0,0,.3,0,0,0,0,0,0,0,.3,0],h:[.6,.4,.6,.4,.6,.4,.6,.4,.6,.4,.6,.4,.6,.4,.6,.4],o:[0,0,0,0,0,0,0,.4,0,0,0,0,0,0,0,.3]}),
'ambient-click':tpP({k:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],s:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],c:[.2,0,0,0,0,0,0,0,0,0,0,0,0,0,.15,0],h:[0,0,.15,0,0,0,0,0,.1,0,0,0,0,0,0,0],o:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}),
'basic':tpP({k:[1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],s:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[0,.3,0,.3,0,.3,0,.3,0,.3,0,.3,0,.3,0,.3],o:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}),
'dusty1':tpP({k:[1,0,0,.3,0,0,.5,0,0,1,0,0,.4,0,0,0],s:[0,0,0,0,.8,0,0,.2,0,0,0,0,.9,0,0,.3],c:[0,0,.2,0,0,0,.3,0,0,0,0,0,.2,0,0,0],h:[.4,.2,.3,.2,.4,.2,.3,.2,.4,.2,.3,.2,.4,.2,.3,.2],o:[0,0,0,0,0,0,0,.2,0,0,0,0,0,0,0,.3]}),
'wonky1':tpP({k:[1,0,0,0,0,0,.6,0,1,0,0,.4,0,0,0,0],s:[0,0,0,0,1,0,0,0,0,0,.3,0,.8,0,0,0],c:[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],h:[.5,.3,.4,.2,.5,.3,.4,.2,.5,.3,.4,.2,.5,.3,.4,.2],o:[0,0,0,0,0,0,0,.3,0,0,0,0,0,0,0,.2]}),
// RG-69's own dusty kick/snare grammar. It shares a loose MPC pocket and dub vocabulary,
// but keeps its industrial 4-on-floor drum arrangement separate from the Ruby engine.
'bluehour':tpP({k:[1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0],s:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0],c:[0,0,0,0,.32,0,0,0,0,0,0,0,.36,0,0,0],h:[.5,0,.34,0,.5,0,.34,.24,.5,0,.34,0,.5,0,.34,.24],o:[0,0,.44,0,0,0,.44,0,0,0,.44,0,0,0,.44,.32]})
};
const BASS_PATS={
'ethiobass':'C2,,Eb2,,G2,,Ab2,,G2,,Eb2,,C2,,,',
'ethiovamp':'C2,,,,,,,Eb2,,,,,G1,,,',
'reggaebass':'C2,,,,G2,,,,C2,,,,Eb2,,,',
'dubbass':'C1,,,,,,,C1,,,,,,,',
'stepperbass':'C2,,,G2,,,Eb2,,,F2,,,C2,,,',
'industrialbass':'C1,,,C1,,,C1,,,C1,,,C1,,,',
'dronebass':'C1,,,,,,,,,,,,,,,',
'afrobass':'C2,,G2,,Eb2,,F2,,C2,,G2,,Eb2,,F2,',
'bossabass':'C2,,G2,,E2,,A2,,D2,,G2,,C2,,,',
'trapbass':'C1,,,,,,,,C1,,C1,C1,,,,,',
'ambientbass':'C1,,,,,,,,,,,,,,,',
'brokenbass':'C2,,G2,,,,Eb2,,F2,,,,C2,,G2,,',
'basic':'C2,,,,G2,,,,C2,,,,Eb2,,,',
'dustybass1':'C2,,G2,,Eb2,,,F2,,C2,,G2,,,Eb2,',
'wonkybass1':'C2,,,G2,,,,Eb2,C2,,,G2,,,,',
// F-minor dub bass for this original engine study: F pedal with Ab + C colour.
'bluehourbass':'F1,,,C2,,Ab1,,,,F1,,,,Eb2,,,'
};
const KEYS_PATS={
// PR #250
'tizita':[['C4','D4','E4','G4'],0,0,0,['G3','A3','C4','D4'],0,0,0],
'bati':[['C4','D4','Eb4','G4'],0,0,0,['Eb4','G4','Ab4','C5'],0,0,0],
'ambassel':[['C4','Db4','F4','G4'],0,0,0,['F3','G3','Ab3','C4'],0,0,0],
'anchihoye':[['C4','Db4','F4','Gb4'],0,0,0,['Gb3','Ab3','C4','Db4'],0,0,0],
'ethiomod':[['C4','Eb4','G4','Bb4'],0,0,0,['Ab3','C4','Eb4','G4'],0,0,0,['Bb3','D4','F4','Ab4'],0,0,0],
'skank':[0,['C4','E4','G4'],0,['C4','E4','G4'],0,['F3','A3','C4'],0,['F3','A3','C4'],0,['G3','B3','D4'],0,['G3','B3','D4'],0,['C4','E4','G4'],0,['C4','E4','G4']],
'roots':[['C4','Eb4','G4'],0,0,0,['Bb3','D4','F4'],0,0,0,['Ab3','C4','Eb4'],0,0,0,['Bb3','D4','F4'],0,0,0],
'dubchord':[['C4','Eb4','G4'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'nyachord':[['C4','Eb4','G4'],0,0,0,0,0,['Ab3','C4','Eb4'],0,0,0,0,0,0,0,0,0],
'indstab':[['C4','Eb4','Gb4'],0,0,0,0,0,0,0,['Bb3','Db4','F4'],0,0,0,0,0,0,0],
'darkchrom':[['C4','Eb4','Gb4'],0,0,0,['Db4','E4','G4'],0,0,0,0,0,0,0,0,0,0,0],
'noisechord':[['C3','Db3','Gb3'],0,0,0,['F3','Gb3','C4'],0,0,0,0,0,0,0,0,0,0,0],
'acid':['C4',0,'Eb4',0,'Gb4',0,'Ab4',0,'C4',0,'Eb4',0,'Gb4',0,'Ab4',0],
'dilla1':[['D4','F4','A4','C5'],0,0,0,['G3','Bb3','D4','F4'],0,0,0,['C4','E4','G4','Bb4'],0,0,0,0,0,0,0],
'neosoul':[['C4','Eb4','G4','Bb4'],0,0,0,['Bb3','D4','F4','Ab4'],0,0,0,['Ab3','C4','Eb4','G4'],0,0,0,['G3','Bb3','D4','F4'],0,0,0],
'gospel':[['F3','A3','C4','E4'],0,0,0,['G3','B3','D4','F4'],0,0,0,['C4','E4','G4','B4'],0,0,0,0,0,0,0],
'badu':[['C4','E4','G4','B4','D5'],0,0,0,['F3','A3','C4','E4','G4'],0,0,0,0,0,0,0,0,0,0,0],
'drunk':[['C4','E4','G4'],0,0,['F3','A3','C4'],0,0,0,['G3','B3','D4'],0,0,0,['C4','E4','G4'],0,0,0],
'bachdown':[['C4','E4','G4'],['B3','D4','G4'],['A3','C4','F4'],['G3','B3','E4'],['F3','A3','D4'],['E3','G3','C4'],['D3','F3','B3'],['C3','E3','A3']],
'bachfugue':[['C4'],0,0,0,['E4'],0,['G4'],0,['C5'],0,0,0,['G4'],0,['E4'],0],
'chorale':[['C4','E4','G4','C5'],0,0,0,['F3','A3','C4','F4'],0,0,0,['G3','B3','D4','G4'],0,0,0,['C4','E4','G4','C5'],0,0,0],
'prelude':[['C4'],['E4'],['G4'],['C5'],['E5'],['G5'],['C5'],['E5'],['G4'],['C5'],['E4'],['G4'],['C4'],['E4'],['G3'],['C4']],
'cadence':[['F3','A3','C4','F4'],0,0,0,['G3','B3','D4','G4'],0,['G3','B3','D4','F4'],0,['C4','E4','G4','C5'],0,0,0,0,0,0,0],
// NEW genre keys
'afrokeys':[['C4','Eb4','G4'],0,['Bb3','D4','F4'],0,['Ab3','C4','Eb4'],0,['Bb3','D4','F4'],0,['C4','Eb4','G4'],0,['Bb3','D4','F4'],0,['Ab3','C4','Eb4'],0,0,0],
'bossachord':[['C4','E4','G4','B4'],0,0,0,['A3','C4','E4','G4'],0,0,0,['D4','F4','A4','C5'],0,0,0,['G3','B3','D4','F4'],0,0,0],
'trapkeys':[['C4','Eb4','Gb4'],0,0,0,0,0,0,0,['Bb3','Db4','F4'],0,0,0,0,0,0,0],
'ambientchord':[['C4','G4','D5','A5'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'brokenkeys':[['C4','Eb4','G4','Bb4'],0,0,['Ab3','C4','Eb4'],0,0,0,['Bb3','D4','F4','A4'],0,0,0,0,['G3','Bb3','D4','F4'],0,0,0],
// Version1 additions - Advanced voicings and melodies
'cluster':[['C4','Db4','D4','Eb4'],0,0,0,['F4','Gb4','G4','Ab4'],0,0,0,['C4','Db4','D4','Eb4'],0,0,0,0,0,0,0],
'v7b9':[['C4','E4','Bb4','Db5'],0,0,0,['F3','A3','Eb4','G4'],0,0,0,['G3','B3','F4','Ab4'],0,0,0,0,0,0,0],
'min9-walk':[['C4','Eb4','Bb4','D5'],0,['Bb3','D4','Ab4','C5'],0,['Ab3','C4','Gb4','Bb4'],0,['G3','B3','F4','A4'],0,['C4','Eb4','Bb4','D5'],0,0,0,0,0],
'canon':[['C4'],0,['D4'],0,['E4'],0,['C4'],0,['E4'],0,['F4'],0,['G4'],0,0,0],
'contrary':[['C4','C5'],['D4','B4'],['E4','A4'],['F4','G4'],['G4','F4'],['A4','E4'],['B4','D4'],['C5','C4']],
'descseq':[['E4'],['D4'],['C4'],['B3'],['A3'],['G3'],['F3'],['E3'],['D3'],['C3'],['B2'],['A2'],0,0,0,0],
'pedaltone':[['C4','E4','G4'],['C4','F3','A3'],['C4','G3','B3'],['C4','E4','G4'],['C4','F3','A3'],['C4','G3','B3'],['C4','E4','G4'],0],
'melodica':[['C4'],['E4'],['G4'],['A4'],['G4'],['E4'],['C4'],0,['D4'],['F4'],['A4'],['Bb4'],['A4'],['F4'],['D4'],0],
// PR #249
'basic':[['C4','E4','G4'],0,0,0,['F3','A3','C4'],0,0,0,['G3','B3','D4'],0,0,0,['C4','E4','G4'],0,0,0],
'dustykeys1':[['C4','Eb4','G4'],0,['Bb3','D4','F4'],0,['Ab3','C4','Eb4'],0,0,0],
// Soul/Gospel progressions
// Preset names nod to artists; the loops are generic genre studies, not claimed
// transcriptions. Sourced artist material lives in data/recovered_music.json
// under the 2026-11-22 ORIGINAL AUTHENTICS directive.
'soulwalk':[['C4','E4','G4','B4'],0,0,0,['A3','C4','E4','G4'],0,0,0,['D4','F4','A4','C5'],0,0,0,['G3','B3','D4','F4'],0,0,0],
'hathaway':[['C4','E4','G4','B4'],0,0,0,['B3','D4','F4','A4'],0,0,0,['A3','C4','E4','G4'],0,0,0,['G3','B3','D4','F4'],0,0,0],
'marvin':[['C4','E4','G4'],0,0,0,['E3','G3','B3'],0,0,0,['F3','A3','C4'],0,0,0,['F3','Ab3','C4'],0,0,0],
'tender':[['C4','Eb4','G4','Bb4','D5'],0,0,0,0,0,0,0,['Ab3','C4','Eb4','G4','Bb4'],0,0,0,0,0,0,0],
'wonder':[['C4','E4','G4','A4','D5'],0,0,0,['F3','A3','C4','E4','G4'],0,0,0,['G3','B3','D4','F4','A4'],0,0,0,['C4','E4','G4','B4'],0,0,0],
// F-minor harmony shared with Dilla's engine-original study; this is not artist-sourced material.
'bluehourkeys':[['F3','Ab3','C4','Eb4','G4'],0,0,0,['Ab3','C4','Eb4','Gb4','F4'],0,0,0,['Db3','F3','Ab3','C4','Eb4','G4'],0,0,0,['C3','E3','G3','Bb3','Db4'],0,0,0]
}
const PAD_PATS={
'none':[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'ethiodrone':[['C3','G3','C4','Eb4'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'dubwash':[['C3','G3','Eb4'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'rootsdrone':[['C3','Eb3','G3'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'industrialdrone':[['C2','Gb2','C3'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'noisewash':[['C2','Db2','Gb2'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'afrodrone':[['C3','G3','Bb3','Eb4'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'bossawash':[['C3','E3','G3','B3'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'ambientwash':[['C3','G3','D4','A4','E5'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
// Version1 additions
'ethiowash':[['C3','Db3','F3','Ab3'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'choir':[['C3','E3','G3','C4','E4'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'souldrone':[['C3','Eb3','G3','Bb3','D4'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
'gospelwash':[['C3','E3','G3','B3'],0,0,0,['A2','C3','E3','G3'],0,0,0,['F2','A2','C3','E3'],0,0,0,['G2','B2','D3','F3'],0,0,0],
'tenderwash':[['C3','Eb3','Bb3','D4'],0,0,0,0,0,0,0,['Ab2','C3','Eb3','G3'],0,0,0,0,0,0,0],
// Low F-minor wash under the RG-69 dub arrangement.
'bluehourwash':[['F2','C3','Ab3','Eb4'],0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
}
const STYLES=[
// Shares the F-minor engine-original harmony and dub palette; its tempo, drum
// grammar and Tone.js performance remain an independent RG-69 arrangement.
{n:'F-minor Dub',m:['Dark','Industrial'],d:'bluehour',b:'bluehourbass',k:'bluehourkeys',p:'bluehourwash',bpm:[92,100],sw:[6,12],dr:[62,80],tm:[18,28]},
{n:'Analog Haze',m:['Lush','Magical'],d:'dusty1',b:'dustybass1',k:'neosoul',p:'ambientwash',bpm:[72,88],sw:[28,44],dr:[35,55],tm:[45,70]},
{n:'Ethio-Jazz',m:['Joyful','Mysterious'],d:'eth-mulatu',b:'ethiobass',k:'tizita',p:'ethiodrone',bpm:[85,110],sw:[15,35],dr:[20,40],tm:[5,15]},
{n:'Ethio-Funk',m:['Groovy','Joyful'],d:'eth-funk',b:'ethiovamp',k:'bati',p:'ethiowash',bpm:[100,120],sw:[20,35],dr:[25,45],tm:[5,15]},
{n:'Reggae',m:['Relaxed','Spiritual'],d:'reg-onedrop',b:'reggaebass',k:'skank',p:'rootsdrone',bpm:[62,75],sw:[10,25],dr:[15,30],tm:[8,18]},
{n:'Steppers',m:['Heavy','Spiritual'],d:'reg-steppers',b:'stepperbass',k:'roots',p:'rootsdrone',bpm:[70,85],sw:[8,18],dr:[20,35],tm:[10,20]},
{n:'Dub',m:['Dark','Spacious'],d:'reg-dub',b:'dubbass',k:'dubchord',p:'dubwash',bpm:[65,80],sw:[5,20],dr:[25,50],tm:[40,70]},
{n:'Industrial',m:['Aggressive','Dark'],d:'hate-pummel',b:'industrialbass',k:'indstab',p:'industrialdrone',bpm:[140,160],sw:[0,5],dr:[60,90],tm:[1,5]},
{n:'Hard Techno',m:['Aggressive','Dark'],d:'hate-grind',b:'dronebass',k:'darkchrom',p:'noisewash',bpm:[145,160],sw:[0,3],dr:[70,95],tm:[1,3]},
{n:'Afrobeat',m:['Joyful','Groovy'],d:'afro-tony',b:'afrobass',k:'afrokeys',p:'afrodrone',bpm:[105,125],sw:[10,25],dr:[20,35],tm:[5,15]},
{n:'Afro-Funk',m:['Groovy','Joyful'],d:'afro-fela',b:'afrobass',k:'afrokeys',p:'afrodrone',bpm:[110,130],sw:[15,30],dr:[25,40],tm:[5,15]},
{n:'Bossa Nova',m:['Relaxed','Joyful'],d:'bossa-clave',b:'bossabass',k:'bossachord',p:'bossawash',bpm:[120,140],sw:[5,15],dr:[10,25],tm:[5,15]},
{n:'Bossa Samba',m:['Groovy','Joyful'],d:'bossa-samba',b:'bossabass',k:'bossachord',p:'bossawash',bpm:[125,145],sw:[8,18],dr:[15,30],tm:[5,15]},
{n:'Trap',m:['Dark','Heavy'],d:'trap-basic',b:'trapbass',k:'trapkeys',p:'industrialdrone',bpm:[130,150],sw:[0,5],dr:[40,70],tm:[1,5]},
{n:'Drill',m:['Dark','Aggressive'],d:'drill-dark',b:'trapbass',k:'trapkeys',p:'noisewash',bpm:[135,155],sw:[0,3],dr:[50,80],tm:[1,3]},
{n:'Broken Beat',m:['Groovy','Complex'],d:'broken-classic',b:'brokenbass',k:'brokenkeys',p:'dubwash',bpm:[115,135],sw:[15,35],dr:[25,45],tm:[10,25]},
{n:'West London',m:['Groovy','Complex'],d:'broken-westldn',b:'brokenbass',k:'neosoul',p:'dubwash',bpm:[118,138],sw:[18,38],dr:[28,48],tm:[12,28]},
{n:'Ambient',m:['Calm','Spacious'],d:'ambient-click',b:'ambientbass',k:'ambientchord',p:'ambientwash',bpm:[60,80],sw:[0,10],dr:[5,20],tm:[30,60]},
{n:'Neo-Soul',m:['Groovy','Relaxed'],d:'dusty1',b:'dustybass1',k:'neosoul',p:'choir',bpm:[85,100],sw:[25,40],dr:[25,45],tm:[15,30]},
{n:'Dusty',m:['Relaxed','Mysterious'],d:'dusty1',b:'dustybass1',k:'dustykeys1',p:'dubwash',bpm:[85,95],sw:[25,40],dr:[30,50],tm:[15,30]},
{n:'Wonky',m:['Complex','Mysterious'],d:'wonky1',b:'wonkybass1',k:'drunk',p:'ambientwash',bpm:[90,105],sw:[20,35],dr:[25,45],tm:[10,25]},
{n:'Basic',m:['Simple','Groovy'],d:'basic',b:'basic',k:'basic',p:'none',bpm:[90,120],sw:[10,30],dr:[15,35],tm:[5,15]}
];

const M={
'ethio':{d:'eth-mulatu',b:'ethiobass',k:'tizita',p:'ethiodrone',bpm:[85,110],sw:[15,35]},
'reggae':{d:'reg-onedrop',b:'reggaebass',k:'skank',p:'rootsdrone',bpm:[62,75],sw:[10,25]},
'dub':{d:'reg-dub',b:'dubbass',k:'dubchord',p:'dubwash',bpm:[65,80],sw:[5,20]},
'steppers':{d:'reg-steppers',b:'stepperbass',k:'roots',p:'rootsdrone',bpm:[70,85],sw:[8,18]},
'industrial':{d:'hate-pummel',b:'industrialbass',k:'indstab',p:'industrialdrone',bpm:[140,160],sw:[0,5]},
'hardtechno':{d:'hate-grind',b:'dronebass',k:'darkchrom',p:'noisewash',bpm:[145,160],sw:[0,3]},
'hatestyle':{d:'hate-grind',b:'dronebass',k:'acid',p:'noisewash',bpm:[150,165],sw:[0,5]},
'dusty':{d:'dusty1',b:'dustybass1',k:'dustykeys1',p:'dubwash',bpm:[85,95],sw:[25,40]},
'wonky':{d:'wonky1',b:'wonkybass1',k:'drunk',p:'ambientwash',bpm:[90,105],sw:[20,35]},
'afrobeat':{d:'afro-tony',b:'afrobass',k:'afrokeys',p:'afrodrone',bpm:[105,125],sw:[10,25]},
'bossanova':{d:'bossa-clave',b:'bossabass',k:'bossachord',p:'bossawash',bpm:[120,140],sw:[5,15]},
'trap':{d:'trap-basic',b:'trapbass',k:'trapkeys',p:'industrialdrone',bpm:[130,150],sw:[0,5]},
'ambient':{d:'ambient-click',b:'ambientbass',k:'ambientchord',p:'ambientwash',bpm:[60,80],sw:[0,10]},
'brokenbeat':{d:'broken-classic',b:'brokenbass',k:'brokenkeys',p:'dubwash',bpm:[115,135],sw:[15,35]},
'baroque':{d:'basic',b:'descseq',k:'canon',p:'choir',bpm:[100,120],sw:[0,8]},
'gospel':{d:'dusty1',b:'dustybass1',k:'gospel',p:'gospelwash',bpm:[72,88],sw:[20,35]},
'soulwalk':{d:'dusty1',b:'dustybass1',k:'soulwalk',p:'souldrone',bpm:[76,92],sw:[25,40]},
'tender':{d:'ambient-click',b:'ambientbass',k:'tender',p:'tenderwash',bpm:[60,75],sw:[15,30]},
 'wonder':{d:'dusty1',b:'dustybass1',k:'wonder',p:'souldrone',bpm:[80,96],sw:[22,38]},
 // RG-69 F-minor Dub mood: shared engine-original harmony, independent techno rhythm.
 'bluehour':{d:'bluehour',b:'bluehourbass',k:'bluehourkeys',p:'bluehourwash',bpm:[92,100],sw:[6,12]}
};

function applyMood(m){
if(!m)return;
pushHistory();
pat_.d=m.d;pat_.b=m.b;pat_.k=m.k;pat_.p=m.p;
if(m.bpm)aud_.bpm=m.bpm[0]+Math.random()*(m.bpm[1]-m.bpm[0]);
if(m.sw!==undefined)aud_.swing=m.sw[0]+Math.random()*(m.sw[1]-m.sw[0]);
syncUIFromState();
log('mood applied','k');
}


const bootStyleCandidates=STYLES.filter(style=>{
const drums=DRUM_PATTERNS[style.d];
const bass=(BASS_PATS[style.b]||'').split(',');
const keys=KEYS_PATS[style.k]||[];
const pads=PAD_PATS[style.p]||[];
return drums&&Object.values(drums).some(pattern=>pattern.some(hit=>hit>0))&&bass.some(note=>note)&&keys.some(note=>note&&note!==0)&&pads.some(note=>note&&note!==0);
});
const bootStylePool=bootStyleCandidates.length?bootStyleCandidates:STYLES;
const bootStyle=bootStylePool[Math.floor(Math.random()*bootStylePool.length)];
let st_={started:false,playing:false,idx:-1,timer:null,layoutIdx:49,heartbeat:null,paintMode:false,tapTimes:[],history:[],historyIdx:-1,stepCount:16,theme:'dark',rafId:null,peakL:0,peakR:0,muteState:{k:0,s:0,c:0,h:0,o:0},randomizeFxPending:false};
let aud_={bpm:bootStyle.bpm[0]+Math.random()*(bootStyle.bpm[1]-bootStyle.bpm[0]),swing:bootStyle.sw[0]+Math.random()*(bootStyle.sw[1]-bootStyle.sw[0]),drive:72,tape:44,comp:78,width:52,reverb:34,delay:26,filter:62,wobble:8,vinyl:12,crackle:8,drift:0.05};
let mix_={drum:80,bass:70,keys:60,pads:55,master:75};
let pat_={d:bootStyle.d,b:bootStyle.b,k:bootStyle.k,p:bootStyle.p};
let seq_={};
['k','s','c','h','o'].forEach(t=>{seq_[t]=Array(16).fill(0).map(()=>({v:0.85+rnd(0,0.15),t:rnd(-15,15),p:100,r:1}))});
['b','keys','p'].forEach(t=>{seq_[t]=Array(16).fill(0).map(()=>({v:0.85+rnd(0,0.15),t:rnd(-15,15),p:100,r:1}))});

let kickN,kickSub,kickClk,kickBody,snareN,snareRng,clapN,hatN,openN,bassN,bassSub,keysN,keysChorus,padsN,padsFlt;
let drumG,bassG,keysG,padsG,masterG,limiter,vinylNoise,crackleNoise,driftLFO,analyser;
let fxRev,fxDly,fxDlyFlt,fxFlt,tapeSat,compPar,sslComp,widener,kickSat,keySat,drumSat,outSat,masterDrive,revSend,dlySend;
let drumTube,kickComp,vintageSat,phaserFX,lofiNoise,lofiComp,tapeWS,padsLFO,kickClkBP,snareRngBP,keysTrem,keysDrive;

const fxPool=['AutoWah','AutoFilter','AutoPanner','Chebyshev','Chorus','Distortion','FeedbackDelay','Phaser','PingPongDelay','Tremolo','Vibrato','StereoWidener'];
let drumFX=[],bassFX=[],keysFX=[],padsFX=[],masterFX=[];

// Each page load selects a playable style at random. The effect pool stays
// out of the boot path; only the explicit randomize action builds extra FX.
function createDefaultFX(){
const drum=[],bass=[],keys=[],pads=[];
const add=(arr,eff,wet)=>{if(eff){eff.wet.value=wet;arr.push(eff);}return arr;};
try{add(drum,new Tone.Distortion(0.12),0.12);}catch(e){log('FX default: '+e.message,'w');}
try{add(drum,new Tone.StereoWidener(0.3),0.35);}catch(e){log('FX default: '+e.message,'w');}
try{add(bass,new Tone.Chorus(1.8,3.5,0.4).start(),0.12);}catch(e){log('FX default: '+e.message,'w');}
try{add(keys,new Tone.Chorus(1.6,2.5,0.5).start(),0.2);}catch(e){log('FX default: '+e.message,'w');}
try{add(keys,new Tone.FeedbackDelay(Tone.Time('8n.').toSeconds(),0.26),0.14);}catch(e){log('FX default: '+e.message,'w');}
try{add(pads,new Tone.Chorus(0.9,3.5,0.6).start(),0.28);}catch(e){log('FX default: '+e.message,'w');}
// Pad ambience uses the shared native Reverb send; no FeedbackCombFilter worklet.
try{add(pads,new Tone.StereoWidener(0.45),0.4);}catch(e){log('FX default: '+e.message,'w');}
return {drum,bass,keys,pads};
}
function installDefaultFX(){
const {drum,bass,keys,pads}=createDefaultFX();
const chain=(g,fx,target)=>{
g.disconnect();
if(!fx.length){g.connect(target);g.connect(revSend);g.connect(dlySend);return;}
let last=g;
fx.forEach(f=>{last.connect(f);last=f;});
last.connect(target);
g.connect(revSend);
g.connect(dlySend);
};
chain(drumG,drum,masterG);
chain(bassG,bass,masterG);
chain(keysG,keys,masterG);
chain(padsG,pads,masterG);
drumFX=drum;bassFX=bass;keysFX=keys;padsFX=pads;masterFX=[];
log('FX default chain (fixed)','k');
}

const layouts=Array.from({length:50},(_,i)=>({id:i+1,gap:4+(i%7),pp:6+(i%5),bh:54+(i%5)*3,sh:46+(i%6)*2,ac:24+i}));
const finalBlend={id:"final",gap:8,pp:8,bh:60,sh:52,ac:35};

const tpCache=new Map();
const tpMemo=(k,v)=>{const key=`${k}-${JSON.stringify(v)}`;if(!tpCache.has(key))tpCache.set(key,tp(v));return tpCache.get(key)};

function readOwner(){try{return JSON.parse(readStorage(INSTANCE_KEY)||"null")}catch(e){log("owner-read: "+e.message,"w");return null}}
function claimOwner(){const o=readOwner();if(o?.id&&o.id!==selfId&&(Date.now()-o.ts)<INSTANCE_TTL){try{bc?.postMessage({t:"stop",to:o.id})}catch(error){console.warn("RG-69 cross-tab message unavailable:",error)}}writeStorage(INSTANCE_KEY,JSON.stringify({id:selfId,ts:Date.now()}))}
function keepOwner(){writeStorage(INSTANCE_KEY,JSON.stringify({id:selfId,ts:Date.now()}))}
function releaseOwner(){const o=readOwner();if(o?.id===selfId)removeStorage(INSTANCE_KEY)}

function applyLayout(cfg,nm){
document.querySelector("main").style.gap=`${cfg.gap}px`;
document.querySelectorAll("section,aside,article").forEach(n=>n.style.padding=`${cfg.pp}px`);
document.querySelectorAll("button").forEach(n=>n.style.minHeight=`${cfg.bh}px`);
document.querySelectorAll(".step").forEach(n=>n.style.minHeight=`${cfg.sh}px`);
document.documentElement.style.setProperty("--acc",`hsl(${cfg.ac} 65% 56%)`);
refreshVizColors();
$id("meta").textContent=`layout: ${nm} / instance: ${selfId.slice(-6)}`;
}


// Helper for efficient deep clone without JSON overhead
function deepClone(obj){
if(obj===null||typeof obj!=='object')return obj;
if(Array.isArray(obj))return obj.map(deepClone);
const cloned={};
for (const key of Object.keys(obj)) cloned[key] = deepClone(obj[key]);
return cloned;
}

function pushHistory(){
const snap={pat:deepClone(pat_),seq:deepClone(seq_),aud:deepClone(aud_),mix:deepClone(mix_)};
st_.history=st_.history.slice(0,st_.historyIdx+1);
st_.history.push(snap);
st_.historyIdx=st_.history.length-1;
if(st_.history.length>50)st_.history.shift(),st_.historyIdx--;
}

function undo(){
if(st_.historyIdx>0){
st_.historyIdx--;
const snap=st_.history[st_.historyIdx];
pat_=deepClone(snap.pat);
seq_=deepClone(snap.seq);
aud_=deepClone(snap.aud);
mix_=deepClone(snap.mix);
syncUIFromState();
log("undo");
}}

function redo(){
if(st_.historyIdx<st_.history.length-1){
st_.historyIdx++;
const snap=st_.history[st_.historyIdx];
pat_=deepClone(snap.pat);
seq_=deepClone(snap.seq);
aud_=deepClone(snap.aud);
mix_=deepClone(snap.mix);
syncUIFromState();
log("redo");
}}

function highlightActiveChip(){
const match=STYLES.find(s=>s.d===pat_.d&&s.b===pat_.b&&s.k===pat_.k&&s.p===pat_.p);
document.querySelectorAll('#styles .style-chip').forEach(c=>c.classList.remove('active'));
if(match){const chip=[...$id('styles').querySelectorAll('.style-chip')].find(c=>c.textContent===match.n);if(chip)chip.classList.add('active');}
}

function syncUIFromState(){
$id('bpm').value=aud_.bpm;$id('bpm-o').textContent=Math.round(aud_.bpm);
$id('swing').value=aud_.swing;$id('swing-o').textContent=Math.round(aud_.swing);
$id('drive').value=aud_.drive;$id('drive-o').textContent=Math.round(aud_.drive);
$id('tape').value=aud_.tape;$id('tape-o').textContent=Math.round(aud_.tape);
$id('comp').value=aud_.comp;$id('comp-o').textContent=Math.round(aud_.comp);
$id('width').value=aud_.width;$id('width-o').textContent=Math.round(aud_.width);
$id('reverb').value=aud_.reverb;$id('reverb-o').textContent=Math.round(aud_.reverb);
$id('delay').value=aud_.delay;$id('delay-o').textContent=Math.round(aud_.delay);
$id('filter').value=aud_.filter;$id('filter-o').textContent=Math.round(aud_.filter);
$id('wobble').value=aud_.wobble;$id('wobble-o').textContent=Math.round(aud_.wobble);
$id('vinyl').value=aud_.vinyl;$id('vinyl-o').textContent=Math.round(aud_.vinyl);
$id('crackle').value=aud_.crackle;$id('crackle-o').textContent=Math.round(aud_.crackle);
$id('drum-vol').value=mix_.drum;$id('drum-vol-o').textContent=Math.round(mix_.drum);
$id('bass-vol').value=mix_.bass;$id('bass-vol-o').textContent=Math.round(mix_.bass);
$id('keys-vol').value=mix_.keys;$id('keys-vol-o').textContent=Math.round(mix_.keys);
$id('pads-vol').value=mix_.pads;$id('pads-vol-o').textContent=Math.round(mix_.pads);
$id('master-vol').value=mix_.master;$id('master-vol-o').textContent=Math.round(mix_.master);
$id('drum-pat').value=pat_.d;
$id('bass-pat').value=pat_.b;
$id('keys-pat').value=pat_.k;
$id('pads-pat').value=pat_.p;
updateRootDisplay();
applyFX();
highlightActiveChip();
}

async function initAudio(activationPromise){
// Tone.start() must be invoked synchronously by the trusted click handler.
await (activationPromise||Tone.start());
Tone.getContext().rawContext.addEventListener('statechange',()=>{
  if(Tone.getContext().rawContext.state==='suspended'){
    st_.playing=false;clearTimeout(st_.timer);$id('play').textContent='▶ Play';st('suspended — tap to resume');log('audio suspended by browser','w');
  }
});
await rg69AudioProfileReady;
const toneProfile=rg69AudioProfile.tone,kitProfile=rg69AudioProfile.kit,voiceProfile=rg69AudioProfile.voice;
driftLFO=new Tone.LFO(0.05,-4,4).start();
const instruments=createToneInstruments();
kickN=instruments.kick;kickSub=instruments.kickSub;kickClk=instruments.kickClk;kickBody=instruments.kickBody;
snareN=instruments.snare;snareRng=instruments.snareRing;clapN=instruments.clap;hatN=instruments.hat;openN=instruments.open;
bassN=instruments.bass;bassSub=instruments.bassSub;keysN=instruments.keys;padsN=instruments.pads;
kickClkBP=new Tone.Filter(toneProfile.kick.click_filter_base_hz+kitProfile.kick.tone*toneProfile.kick.click_filter_tone_span_hz,'bandpass');
kickClkBP.Q.value=toneProfile.kick.click_filter_q;kickClk.connect(kickClkBP);
snareRngBP=new Tone.Filter(toneProfile.snare.ring_filter_base_hz+kitProfile.snare.tone*toneProfile.snare.ring_filter_tone_span_hz,'bandpass');
snareRngBP.Q.value=toneProfile.snare.ring_filter_q;snareRng.connect(snareRngBP);
keysChorus=new Tone.Chorus(toneProfile.keys.chorus_frequency,toneProfile.keys.chorus_delay_time,toneProfile.keys.chorus_depth).start();
keysTrem=new Tone.Tremolo({frequency:toneProfile.keys.tremolo_frequency,depth:toneProfile.keys.tremolo_depth,wet:toneProfile.keys.tremolo_wet,spread:toneProfile.keys.tremolo_spread});keysTrem.start();
keysDrive=new Tone.Distortion(toneProfile.keys.drive_amount);keysDrive.wet.value=toneProfile.keys.drive_wet;
padsFlt=new Tone.Filter(toneProfile.pads.filter_base_hz+voiceProfile.brightness*toneProfile.pads.filter_brightness_span_hz,'lowpass');
padsLFO=new Tone.LFO(0.12,600,1400);padsLFO.start();padsLFO.connect(padsFlt.frequency);

kickSat=new Tone.Chebyshev(2);
keySat=new Tone.Chebyshev(2);
drumSat=new Tone.Chebyshev(3);
kickComp=new Tone.Compressor(-30,8);
kickComp.attack.value=.001;
drumG=new Tone.Gain(Tone.dbToGain(-6));
bassG=new Tone.Gain(Tone.dbToGain(-8));
keysG=new Tone.Gain(Tone.dbToGain(-10));
padsG=new Tone.Gain(Tone.dbToGain(-12));
revSend=new Tone.Gain(0);
dlySend=new Tone.Gain(0);
fxRev=new Tone.Reverb(1.5);
fxDly=new Tone.FeedbackDelay(Tone.Time('8n').toSeconds(),0.2);
fxFlt=new Tone.Filter(16000,'lowpass');
tapeSat=new Tone.Distortion(0.08);
compPar=new Tone.Compressor(-18,4);
sslComp=new Tone.Compressor(-18,4);
sslComp.attack.value=0.01;
sslComp.release.value=0.3;
widener=new Tone.StereoWidener(0.4);
masterDrive=new Tone.Distortion(0.04);
limiter=new Tone.Limiter(-1);
outSat=new Tone.Distortion(0.01);
vintageSat=new Tone.Chebyshev(2);
vintageSat.wet.value=0.3;
phaserFX=new Tone.Phaser({frequency:0.5,octaves:2,baseFrequency:350,stages:4});
phaserFX.wet.value=0.15;
lofiComp=new Tone.Compressor(-24,3);
lofiComp.attack.value=0.003;
lofiComp.release.value=0.1;
tapeWS=new Tone.WaveShaper((val)=>Math.tanh(val*1.5),4096);
tapeWS.oversample='none';
masterG=new Tone.Gain(0.8).connect(masterDrive);
masterDrive.wet.value=0;
masterDrive.connect(outSat);
outSat.connect(limiter);
limiter.connect(Tone.Destination);
masterG.disconnect();
masterG.connect(fxFlt);
fxFlt.connect(vintageSat);
vintageSat.connect(phaserFX);
phaserFX.connect(lofiComp);
lofiComp.connect(tapeWS);
tapeWS.connect(tapeSat);
tapeSat.connect(compPar);
compPar.connect(sslComp);
sslComp.connect(widener);
widener.connect(masterDrive);
widener.connect(analyser=new Tone.Analyser('waveform',256));
revSend.connect(fxRev);
fxRev.connect(compPar);
dlySend.connect(fxDly);
fxDlyFlt=new Tone.Filter(rg69AudioProfile.rig.delay.lowpass,'lowpass');
fxDly.connect(fxDlyFlt);
fxDlyFlt.connect(compPar);
if(fxRev&&typeof fxRev.generate==="function")await fxRev.generate();
lofiNoise=new Tone.Noise('pink').start();
lofiNoise.volume.value=-45;
const lofiNoiseLP=new Tone.Filter(4000,'lowpass');
lofiNoise.connect(lofiNoiseLP);
lofiNoiseLP.connect(compPar);
vinylNoise=new Tone.Noise('brown').start();
vinylNoise.volume.value=-40;
const vinylFlt=new Tone.Filter(2000,'lowpass');
vinylNoise.connect(vinylFlt);
crackleNoise=new Tone.Noise('white').start();
crackleNoise.volume.value=-45;
const crackFlt=new Tone.Filter(380,'bandpass');
crackFlt.Q.value=5;
crackleNoise.connect(crackFlt);
vinylFlt.connect(compPar);
crackFlt.connect(compPar);
driftLFO.connect(kickN.oscillator.detune);
driftLFO.connect(snareRng.detune);
[kickN,kickSub,kickClkBP,kickBody].forEach(s=>s.connect(kickSat));
kickSat.connect(kickComp);
kickComp.connect(drumG);
[snareN,snareRngBP,clapN,hatN,openN].forEach(s=>s.connect(drumSat));
drumSat.connect(drumG);
bassN.connect(bassG);
bassSub.connect(bassG);
keysN.connect(keySat);
keySat.connect(keysChorus);
keysChorus.connect(keysTrem);
keysTrem.connect(keysDrive);
keysDrive.connect(keysG);
// Warm, worklet-free saturation + 5kHz bandwidth limit on keys
const keysTexture=new Tone.Distortion(toneProfile.keys.texture_amount);keysTexture.wet.value=toneProfile.keys.texture_wet;
const keysLP=new Tone.Filter(toneProfile.keys.filter_base_hz+voiceProfile.brightness*toneProfile.keys.filter_brightness_span_hz,'lowpass');
keysG.connect(keysTexture);keysTexture.connect(keysLP);keysLP.connect(masterG);keysLP.connect(revSend);keysLP.connect(dlySend);
padsN.connect(padsFlt);
padsFlt.connect(padsG);
// old-sampler: 3.5kHz bandwidth + warmth on pads
const padsBW=new Tone.Filter(toneProfile.pads.lowpass_hz,'lowpass');
const padsSat=new Tone.Chebyshev(toneProfile.pads.saturation_order);padsSat.wet.value=toneProfile.pads.saturation_wet;
padsG.connect(padsBW);padsBW.connect(padsSat);padsSat.connect(masterG);padsSat.connect(revSend);padsSat.connect(dlySend);
// route remaining tracks
[drumG,bassG].forEach(g=>{g.connect(masterG);g.connect(revSend);g.connect(dlySend);});
installDefaultFX();
if(st_.randomizeFxPending){st_.randomizeFxPending=false;randomizeFX();}else applyFX();
log("audio engine init (analog++)","k");
}

function applyFX(){
const profile=rg69AudioProfile;
if(st_.started)Tone.Transport.bpm.value=aud_.bpm;
if(drumG)drumG.gain.value=mix_.drum/100;
if(bassG)bassG.gain.value=mix_.bass/100;
if(keysG)keysG.gain.value=mix_.keys/100*profile.voice.level;
if(padsG)padsG.gain.value=mix_.pads/100*profile.voice.level;
if(masterG)masterG.gain.value=mix_.master/100;
if(revSend)revSend.gain.value=(aud_.reverb/100)*profile.rig.reverb.level_chords;
if(dlySend)dlySend.gain.value=(aud_.delay/100)*profile.rig.delay.throw_chords;
if(fxRev){fxRev.wet.value=1;fxRev.decay=1+(aud_.reverb/100)*profile.rig.reverb.size*profile.effects.reverb_decay_scale;}
if(fxDly){fxDly.wet.value=1;fxDly.feedback.value=profile.rig.delay.feedback+(aud_.delay/100)*profile.effects.delay_feedback_range;}
if(fxDlyFlt)fxDlyFlt.frequency.value=profile.rig.delay.lowpass;
if(fxFlt)fxFlt.frequency.value=PARAMS.FILTER_MIN_HZ+aud_.filter/100*PARAMS.FILTER_MAX_HZ;
if(tapeSat)tapeSat.wet.value=aud_.tape/100;
if(compPar)compPar.ratio.value=1+aud_.comp/100*PARAMS.COMP_RATIO_MAX;
if(widener)widener.width.value=aud_.width/100;
if(vinylNoise)vinylNoise.volume.value=-60+aud_.vinyl/100*20;
if(crackleNoise)crackleNoise.volume.value=-65+aud_.crackle/100*20;
if(masterDrive)masterDrive.wet.value=(100-aud_.drive)/400;
if(driftLFO)driftLFO.frequency.value=.05+aud_.wobble/100*Math.min(rg69AudioProfile.rig.wobble.rate_hz,rg69AudioProfile.effects.wobble_frequency_cap_hz);
}

// Shared helper function for triggering notes - eliminates duplication between scheduleLoop and exportWAV
function swingOffsetSeconds(stepIdx,sixteenth,intensity,enabled){
if(!enabled||stepIdx%2===0)return 0;
const mpcSwing=50+Math.max(0,Math.min(100,Number(intensity)||0))*0.16;
const position=0.5+((mpcSwing-50)/16)*(2/3-0.5);
return (position-0.5)*sixteenth*2;
}

function triggerNotes(stepIdx,baseTime,synths,opts){
const sixteenth=opts.sixteenth||60/aud_.bpm/4;
const swungTime=baseTime+swingOffsetSeconds(stepIdx,sixteenth,aud_.swing,opts.addSwing);
// Resolve note lengths to seconds before scheduling. Tone's musical-time
// parser consults Transport when given strings such as "8n"; doing that
// inside a Transport callback causes timing warnings and extra work.
const eighth=sixteenth*2;
const thirtySecond=sixteenth/2;
const sixteenthDuration=sixteenth;
const half=sixteenth*8;
const dp=DRUM_PATTERNS[pat_.d]||DRUM_PATTERNS.basic;
['k','s','c','h','o'].forEach(v=>{
if(opts.muteMap&&opts.muteMap[v])return;
const vel=dp[v]?dp[v][stepIdx]:0;
const prob=seq_[v][stepIdx].p||100;
if(vel>0&&(!opts.applyProb||Math.random()*100<prob)){
const drift=opts.applyTranspose?(Math.random()-0.5)*5:0;
const t=swungTime+seq_[v][stepIdx].t/1000;
const vl=vel*seq_[v][stepIdx].v;
const ratch=opts.applyRatchet?seq_[v][stepIdx].r||1:1;
for(let r=0;r<ratch;r++){
const rt=t+r*(sixteenth/ratch);
if(v==='k'){
const kpitch='C1';
const kfreq=opts.applyTranspose?Tone.Frequency(kpitch).toFrequency()*(1+drift/1200):Tone.Frequency(kpitch).toFrequency();
synths.kick.triggerAttackRelease(kfreq,eighth,rt,vl);
synths.kickSub.triggerAttackRelease(opts.applyTranspose?Tone.Frequency(kpitch).transpose(-12):'C0',eighth,rt,vl*.7);
synths.kickClk.triggerAttackRelease(thirtySecond,rt,vl*0.3);
synths.kickBody.triggerAttackRelease(opts.applyTranspose?Tone.Frequency(kpitch).transpose(12):'C2',thirtySecond,rt,vl*.2);
}
else if(v==='s'){synths.snare.triggerAttackRelease(eighth,rt,vl);synths.snareRng.triggerAttackRelease('E4',sixteenthDuration,rt,vl*0.5)}
else if(v==='c')synths.clap.triggerAttackRelease(sixteenthDuration,rt,vl);
else if(v==='h')synths.hat.triggerAttackRelease(200,sixteenthDuration,rt,vl);
else if(v==='o')synths.open.triggerAttackRelease(200,eighth,rt,vl);
}
}
});
const bn=BASS_PATS[pat_.b]?.split(',')||[];
if(bn[stepIdx]&&bn[stepIdx]!==''){
const nt=bn[stepIdx];
const drift=opts.applyTranspose?(Math.random()-0.5)*2:0;
const freq=opts.applyTranspose?Tone.Frequency(nt).toFrequency()*(1+drift/1200):Tone.Frequency(nt).toFrequency();
synths.bass.triggerAttackRelease(freq,eighth,swungTime+seq_.b[stepIdx].t/1000,seq_.b[stepIdx].v);
synths.bassSub.frequency.setValueAtTime(Tone.Frequency(nt).toFrequency()/2,swungTime+seq_.b[stepIdx].t/1000);
}
const kn=KEYS_PATS[pat_.k]||[];
if(kn[stepIdx]&&kn[stepIdx]!==0){
const ch=kn[stepIdx];
if(Array.isArray(ch)){
synths.keys.triggerAttackRelease(ch,eighth,swungTime+seq_.keys[stepIdx].t/1000,seq_.keys[stepIdx].v);
}else if(typeof ch==='string'){
synths.keys.triggerAttackRelease(ch,eighth,swungTime+seq_.keys[stepIdx].t/1000,seq_.keys[stepIdx].v);
}
}
const pn=PAD_PATS[pat_.p]||[];
if(pn[stepIdx]&&pn[stepIdx]!==0){
const pad=pn[stepIdx];
if(Array.isArray(pad)){
synths.pads.triggerAttackRelease(pad,half,swungTime+seq_.p[stepIdx].t/1000,seq_.p[stepIdx].v*0.6);
}
}
}

function scheduleLoop(time){
st_.idx=(st_.idx+1)%st_.stepCount;
const scheduledTime=Number.isFinite(time)?time:Tone.now();
// Update the small transport display on beats, not every sixteenth note.
const posEl=$id('pos-display');
if(st_.idx%4===0){
const beat=Math.floor(st_.idx/4)+1;
const bar=Math.floor((st_.barCount||0)/16)+1;
if(st_.idx===0)st_.barCount=(st_.barCount||0)+16;
if(posEl)posEl.textContent=`${bar}.${beat}`;
posEl?.classList.add('beat-active');
}else{
posEl?.classList.remove('beat-active');
}
const sixteenth=60/aud_.bpm/4;
triggerNotes(st_.idx,scheduledTime,{
kick:kickN,
kickSub:kickSub,
kickClk:kickClk,
kickBody:kickBody,
snare:snareN,
snareRng:snareRng,
clap:clapN,
hat:hatN,
open:openN,
bass:bassN,
bassSub:bassSub,
keys:keysN,
pads:padsN
},{
muteMap:st_.muteState,
applyProb:true,
applyRatchet:true,
sixteenth:sixteenth,
addSwing:true,
applyTranspose:true
});
st_.uiDirty=true;
// Timing callback: no canvas work, analyser reads, or per-step DOM repaint.
}

let stepUiByIndex=Array.from({length:16},()=>[]);
let activeStepUiIndex=-1;
function updateStepUI(){
const next=st_.idx%16;
if(activeStepUiIndex>=0)stepUiByIndex[activeStepUiIndex].forEach(el=>el.classList.remove('playing'));
stepUiByIndex[next].forEach(el=>el.classList.add('playing'));
activeStepUiIndex=next;
}

function updateVisuals(){
if(!st_.playing){st_.rafId=null;return;}
const now=performance.now();
if(now-(st_.visualLastUpdate||0)>=50){
st_.visualLastUpdate=now;
const data=analyser?.getValue();
if(data&&data.length){
let sumSquares=0;
let clipping=false;
for(let i=0;i<data.length;i++){
const sample=data[i];
sumSquares+=sample*sample;
if(Math.abs(sample)>=0.98)clipping=true;
}
const rms=Math.sqrt(sumSquares/data.length);
st_.peakL=Math.max(st_.peakL*PARAMS.VU_DECAY,rms);
st_.peakR=Math.max(st_.peakR*PARAMS.VU_DECAY,rms);
if(vizContext&&vizCanvas){
const width=vizCanvas.width,height=vizCanvas.height;
vizContext.fillStyle=vizColors.background;
vizContext.fillRect(0,0,width,height);
vizContext.beginPath();
vizContext.strokeStyle=clipping?'#e06c5a':vizColors.accent;
vizContext.lineWidth=1.5;
for(let i=0;i<data.length;i++){
const x=(i/data.length)*width;
const y=(1-(data[i]+1)/2)*height;
if(i===0)vizContext.moveTo(x,y);else vizContext.lineTo(x,y);
}
vizContext.stroke();
}
}
const bars=$id('vu').children;
const leftBars=Math.round(st_.peakL*PARAMS.VU_BARS);
const rightBars=Math.round(st_.peakR*PARAMS.VU_BARS);
for(let i=0;i<PARAMS.VU_BARS;i++){
if(bars[i])bars[i].classList.toggle('active',i<leftBars);
if(bars[i+PARAMS.VU_BARS])bars[i+PARAMS.VU_BARS].classList.toggle('active',i<rightBars);
}
if(st_.uiDirty){
updateStepUI();
st_.uiDirty=false;
}
}
st_.rafId=requestAnimationFrame(updateVisuals);
}

function updateRootDisplay(){
const el=$id('root-display');
if(!el)return;
const k=pat_.k||'';
// derive root from first chord of current keys pattern
const kp=KEYS_PATS[k];
if(kp){const first=kp.find(v=>v&&v!==0);if(first){const note=Array.isArray(first)?first[0]:first;el.textContent=note.replace(/\d/,'');return;}}
el.textContent='';
}

// Stop VU meter updates when page unloads
window.addEventListener('beforeunload',()=>{
if(st_.rafId){
cancelAnimationFrame(st_.rafId);
st_.rafId=null;
}
});

function randomize(){
const style=STYLES[Math.floor(Math.random()*STYLES.length)];
pushHistory();
const isLocked=sec=>document.querySelector(`.lock-btn[data-lock="${sec}"]`)?.classList.contains('locked');
if(!isLocked('drum'))pat_.d=style.d;
if(!isLocked('bass'))pat_.b=style.b;
if(!isLocked('keys'))pat_.k=style.k;
if(!isLocked('pads'))pat_.p=style.p;
aud_.bpm=style.bpm[0]+Math.random()*(style.bpm[1]-style.bpm[0]);
aud_.swing=style.sw[0]+Math.random()*(style.sw[1]-style.sw[0]);
aud_.drive=style.dr[0]+Math.random()*(style.dr[1]-style.dr[0]);
aud_.tape=style.tm[0]+Math.random()*(style.tm[1]-style.tm[0]);
syncUIFromState();
['k','s','c','h','o','b','keys','p'].forEach(t=>{
seq_[t]=seq_[t].map(()=>({v:0.85+rnd(0,0.15),t:rnd(-15,15),p:100,r:1}));
});
log(`random: ${style.n}`,"k");
randomizeFX();
}

function randomizeFX(){
if(!drumG||!bassG||!keysG||!padsG||!masterG){st_.randomizeFxPending=true;return;}
const clearFXArray=(arr)=>arr.forEach(fx=>{try{fx.disconnect();fx.dispose();}catch(e){log('FX cleanup: '+e.message,'w');}});
[drumFX,bassFX,keysFX,padsFX,masterFX].forEach(clearFXArray);
drumFX.length=bassFX.length=keysFX.length=padsFX.length=masterFX.length=0;
const createFX=(isMaster)=>{
const num=isMaster?0:1+Math.floor(Math.random()*2);
const wet=isMaster?0.08+Math.random()*0.19:0.15+Math.random()*0.35;
const fx=[];
for(let i=0;i<num;i++){
const type=fxPool[Math.floor(Math.random()*fxPool.length)];
let eff;
try{
switch(type){
case'AutoWah':eff=new Tone.AutoWah(60+Math.random()*340,2+Math.random()*4,-40+Math.random()*30);break;
case'AutoFilter':eff=new Tone.AutoFilter(0.1+Math.random()*7.9);if(eff.depth)eff.depth.value=0.3+Math.random()*0.7;eff.baseFrequency=100+Math.random()*1900;eff.start();break;
case'AutoPanner':eff=new Tone.AutoPanner(0.2+Math.random()*5.8);if(eff.depth)eff.depth.value=0.4+Math.random()*0.6;eff.start();break;
case'Chebyshev':eff=new Tone.Chebyshev(2+Math.floor(Math.random()*7));break;
case'Chorus':eff=new Tone.Chorus(1+Math.random()*5,1+Math.random()*4,0.3+Math.random()*0.6);eff.start();break;
case'Distortion':eff=new Tone.Distortion(0.1+Math.random()*0.7);break;
case'FeedbackDelay':{const dt=Tone.Time(['8n','16n','8n.','4n'][Math.floor(Math.random()*4)]).toSeconds();eff=new Tone.FeedbackDelay(dt,0.15+Math.random()*0.45);}break;


case'Phaser':eff=new Tone.Phaser({frequency:0.2+Math.random()*3.8,octaves:1+Math.random()*4,baseFrequency:200+Math.random()*1300});break;
case'PingPongDelay':{const dt=Tone.Time(['8n','16n','8n.','4n'][Math.floor(Math.random()*4)]).toSeconds();eff=new Tone.PingPongDelay(dt,0.1+Math.random()*0.4);}break;
case'Tremolo':eff=new Tone.Tremolo(0.5+Math.random()*11.5,0.3+Math.random()*0.6);eff.start();break;
case'Vibrato':eff=new Tone.Vibrato(1+Math.random()*9,0.05+Math.random()*0.35);break;
case'StereoWidener':eff=new Tone.StereoWidener(0.3+Math.random()*0.6);break;
}
if(eff){eff.wet.value=wet;fx.push(eff);}
}catch(e){log('FX create: '+e.message,'w');}
}
return fx;
};
drumFX=createFX(0);
bassFX=createFX(0);
keysFX=createFX(0);
padsFX=createFX(0);
masterFX=[];
const chainFX=(g,fx,target)=>{
g.disconnect();
if(!fx.length){g.connect(target);g.connect(revSend);g.connect(dlySend);return;}
let last=g;
fx.forEach(f=>{last.connect(f);last=f;});
last.connect(target);
g.connect(revSend);
g.connect(dlySend);
};
chainFX(drumG,drumFX,masterG);
chainFX(bassG,bassFX,masterG);
chainFX(keysG,keysFX,masterG);
chainFX(padsG,padsFX,masterG);
applyFX();
log('FX randomized','k');
}

async function exportWAV(){
try{
const bars=8,len=bars*4*(60/aud_.bpm);
$id('progress-wrap').style.display='block';
$id('progress-pct').textContent='0%';
$id('progress-fill').style.width='0%';
log("exporting WAV...","i");
const buf=await Tone.Offline(async()=>{
// Create isolated audio graph for offline rendering - never touch global synth variables
const oDrumG=new Tone.Gain(mix_.drum/100);
const oBassG=new Tone.Gain(mix_.bass/100);
const oKeysG=new Tone.Gain(mix_.keys/100);
const oPadsG=new Tone.Gain(mix_.pads/100);
const oMaster=new Tone.Gain(mix_.master/100);
const oFlt=new Tone.Filter(50+aud_.filter/100*15950,'lowpass');
const oTape=new Tone.Distortion(0.08);
const oComp=new Tone.Compressor(-18,1+aud_.comp/100*7);
const oLimiter=new Tone.Limiter(-1);
const oRevSend=new Tone.Gain((aud_.reverb/100)*0.35);
const oDlySend=new Tone.Gain((aud_.delay/100)*0.28);
const oRev=new Tone.Reverb(1+(aud_.reverb/100)*4);
const oDly=new Tone.FeedbackDelay(Tone.Time('8n').toSeconds(),0.1+(aud_.delay/100)*0.55);
oRev.wet.value=1;
oDly.wet.value=1;
oTape.wet.value=aud_.tape/100;
oMaster.connect(oFlt);
oFlt.connect(oTape);
oTape.connect(oComp);
oComp.connect(oLimiter);
oLimiter.toDestination();
oRevSend.connect(oRev);
oDlySend.connect(oDly);
oRev.connect(oComp);
oDly.connect(oComp);
// Create isolated synths in offline context
const oKickN=new Tone.MembraneSynth({pitchDecay:.05,octaves:6,oscillator:{type:'sine'},envelope:{attack:.001,decay:.4,sustain:0,release:.1}});
const oKickSub=new Tone.Synth({oscillator:{type:'sine'},envelope:{attack:.001,decay:.5,sustain:0,release:.1}});
const oKickClk=new Tone.NoiseSynth({noise:{type:'white'},envelope:{attack:.001,decay:.02,sustain:0}});
const oKickBody=new Tone.Synth({oscillator:{type:'triangle'},envelope:{attack:.001,decay:.08,sustain:0}});
const oSnareN=new Tone.NoiseSynth({noise:{type:'white'},envelope:{attack:.001,decay:.2,sustain:0}});
const oSnareRng=new Tone.Synth({oscillator:{type:'triangle'},envelope:{attack:.001,decay:.15,sustain:0}});
const oClapN=new Tone.NoiseSynth({noise:{type:'pink'},envelope:{attack:.001,decay:.15,sustain:0}});
const oHatN=new Tone.MetalSynth({frequency:200,envelope:{attack:.001,decay:.1,release:.01},harmonicity:5.1,modulationIndex:32,resonance:4000,octaves:1.5});
const oOpenN=new Tone.MetalSynth({frequency:200,envelope:{attack:.001,decay:.3,release:.2},harmonicity:5.1,modulationIndex:32,resonance:4000,octaves:1.5});
const oBassN=new Tone.MonoSynth({oscillator:{type:'sawtooth'},envelope:{attack:.01,decay:.1,sustain:.5,release:.1}});
const oBassSub=new Tone.Oscillator(40,'sine').start();
oBassSub.volume.value=-12;
const oKeysN=new Tone.PolySynth({maxPolyphony:8,voice:Tone.Synth,options:{oscillator:{type:'triangle'},envelope:{attack:.01,decay:.2,sustain:.3,release:.5}}});
const oPadsN=new Tone.PolySynth({maxPolyphony:4,voice:Tone.Synth,options:{oscillator:{type:'sine'},envelope:{attack:.5,decay:.5,sustain:.8,release:2}}});
const oDrumSat=new Tone.Chebyshev(3);
const oKeySat=new Tone.Chebyshev(2);
const oKickSat=new Tone.Chebyshev(2);
const oKickComp=new Tone.Compressor(-30,8);
const oKeysChorus=new Tone.Chorus(2.5,.3,.3).start();
const oPadsFlt=new Tone.Filter(800,'lowpass');
oKickN.connect(oKickSat);oKickSub.connect(oKickSat);oKickClk.connect(oKickSat);oKickBody.connect(oKickSat);
oKickSat.connect(oKickComp);oKickComp.connect(oDrumG);
oSnareN.connect(oDrumSat);oSnareRng.connect(oDrumSat);oClapN.connect(oDrumSat);oHatN.connect(oDrumSat);oOpenN.connect(oDrumSat);
oDrumSat.connect(oDrumG);
oBassN.connect(oBassG);oBassSub.connect(oBassG);
oKeysN.connect(oKeySat);oKeySat.connect(oKeysChorus);oKeysChorus.connect(oKeysG);
oPadsN.connect(oPadsFlt);oPadsFlt.connect(oPadsG);
for(const g of [oDrumG,oBassG,oKeysG,oPadsG]){g.connect(oMaster);g.connect(oRevSend);g.connect(oDlySend);}
// Schedule all steps using the shared triggerNotes helper
for(let i=0;i<bars*16;i++){
const sixteenth=60/aud_.bpm/4;
const now=i*sixteenth;
triggerNotes(i%16,now,{
kick:oKickN,
kickSub:oKickSub,
kickClk:oKickClk,
kickBody:oKickBody,
snare:oSnareN,
snareRng:oSnareRng,
clap:oClapN,
hat:oHatN,
open:oOpenN,
bass:oBassN,
bassSub:oBassSub,
keys:oKeysN,
pads:oPadsN
},{
muteMap:null,
applyProb:false,
applyRatchet:false,
sixteenth:sixteenth,
addSwing:true,
applyTranspose:false
});
const pct=Math.round((i/(bars*16))*100);
if(i%(bars*2)===0){
$id('progress-pct').textContent=`${pct}%`;
$id('progress-fill').style.width=`${pct}%`;
}
}
},len,2,44100);
const wav=Tone.Buffer.toWav(buf);
const blob=new Blob([wav],{type:'audio/wav'});
const url=URL.createObjectURL(blob);
const a=document.createElement('a');
a.href=url;
const activeChip=document.querySelector('#styles .style-chip.active,#moods .style-chip.active');
const styleName=activeChip?activeChip.textContent.toLowerCase().replace(/\s+/g,'-'):'loop';
a.download=`rg69-${styleName}-${Date.now()}.wav`;
a.click();
URL.revokeObjectURL(url);
$id('progress-wrap').style.display='none';
log("WAV exported","k");
}catch(err){
log("export failed: "+err.message,"e");
$id('progress-wrap').style.display='none';
}
}

let mediaRecorder=null;
let recordedChunks=[];

async function toggleRecord(){
try{
if(!st_.started){
log("start engine first","w");
return;
}
if(!mediaRecorder){
const dest=Tone.context.createMediaStreamDestination();
masterG.connect(dest);
mediaRecorder=new MediaRecorder(dest.stream);
recordedChunks=[];
mediaRecorder.ondataavailable=e=>{
if(e.data.size>0)recordedChunks.push(e.data);
};
mediaRecorder.onstop=()=>{
const blob=new Blob(recordedChunks,{type:'video/webm'});
const url=URL.createObjectURL(blob);
const a=document.createElement('a');
a.href=url;
a.download=`rg69-${Date.now()}.webm`;
a.click();
URL.revokeObjectURL(url);
log("recording saved","k");
$id('record').textContent='● Record';
};
mediaRecorder.start();
$id('record').textContent='■ Stop';
log("recording...","i");
}else{
mediaRecorder.stop();
mediaRecorder=null;
}
}catch(err){
log("Record failed: "+err.message,"e");
mediaRecorder=null;
$id('record').textContent='● Record';
}
}

function buildUI(){
const sel_d=$id('drum-pat'),sel_b=$id('bass-pat'),sel_k=$id('keys-pat'),sel_p=$id('pads-pat');
Object.keys(DRUM_PATTERNS).forEach(k=>{const o=document.createElement('option');o.value=k;o.textContent=k;sel_d.appendChild(o)});
Object.keys(BASS_PATS).forEach(k=>{const o=document.createElement('option');o.value=k;o.textContent=k;sel_b.appendChild(o)});
Object.keys(KEYS_PATS).forEach(k=>{const o=document.createElement('option');o.value=k;o.textContent=k;sel_k.appendChild(o)});
Object.keys(PAD_PATS).forEach(k=>{const o=document.createElement('option');o.value=k;o.textContent=k;sel_p.appendChild(o)});
sel_d.value=pat_.d;sel_b.value=pat_.b;sel_k.value=pat_.k;sel_p.value=pat_.p;
sel_d.addEventListener('change',e=>{pushHistory();pat_.d=e.target.value;log(`drum: ${pat_.d}`)});
sel_b.addEventListener('change',e=>{pushHistory();pat_.b=e.target.value;log(`bass: ${pat_.b}`)});
sel_k.addEventListener('change',e=>{pushHistory();pat_.k=e.target.value;log(`keys: ${pat_.k}`)});
sel_p.addEventListener('change',e=>{pushHistory();pat_.p=e.target.value;log(`pads: ${pat_.p}`)});
const styles_c=$id('styles');
const filterStyles=q=>{
const query=q.toLowerCase();
styles_c.querySelectorAll('.style-chip').forEach(chip=>{
const txt=chip.textContent.toLowerCase();
const mood=chip.title.toLowerCase();
chip.style.display=(txt.includes(query)||mood.includes(query))?'':'none';
});
};
$id('style-search').addEventListener('input',debounce(e=>filterStyles(e.target.value),150));
// Tab switching
$id('tab-styles').addEventListener('click',()=>{$id('styles').style.display='flex';$id('moods').style.display='none';$id('tab-styles').classList.add('active');$id('tab-moods').classList.remove('active');$id('style-search').placeholder='Search styles…'});
$id('tab-moods').addEventListener('click',()=>{$id('moods').style.display='flex';$id('styles').style.display='none';$id('tab-moods').classList.add('active');$id('tab-styles').classList.remove('active');$id('style-search').placeholder='Search moods…'});
STYLES.forEach(s=>{
const chip=document.createElement('div');
chip.className='style-chip';
chip.textContent=s.n;
chip.title=s.m.join(', ');
chip.setAttribute('role','button');
chip.setAttribute('tabindex','0');
chip.addEventListener('keydown',event=>{
if(event.key==='Enter'||event.key===' '){event.preventDefault();chip.click();}
});
chip.addEventListener('click',()=>{
pushHistory();
pat_.d=s.d;pat_.b=s.b;pat_.k=s.k;pat_.p=s.p;
aud_.bpm=s.bpm[0]+Math.random()*(s.bpm[1]-s.bpm[0]);
aud_.swing=s.sw[0]+Math.random()*(s.sw[1]-s.sw[0]);
aud_.drive=s.dr[0]+Math.random()*(s.dr[1]-s.dr[0]);
aud_.tape=s.tm[0]+Math.random()*(s.tm[1]-s.tm[0]);
syncUIFromState();
log(`style: ${s.n}`,"k");
});
styles_c.appendChild(chip);
});
const defaultChip=[...styles_c.querySelectorAll('.style-chip')].find(c=>c.textContent===bootStyle.n);
if(defaultChip)defaultChip.classList.add('active');
const moods_c=$id('moods');
Object.keys(M).forEach(name=>{
const chip=document.createElement('div');
chip.className='style-chip';
chip.textContent=name;
chip.setAttribute('role','button');
chip.setAttribute('tabindex','0');
chip.addEventListener('keydown',event=>{
if(event.key==='Enter'||event.key===' '){event.preventDefault();chip.click();}
});
chip.addEventListener('click',()=>{
applyMood(M[name]);
document.querySelectorAll('#moods .style-chip').forEach(c=>c.classList.remove('active'));
chip.classList.add('active');
log('mood: '+name,'k');
});
moods_c.appendChild(chip);
});
const tracks_c=$id('tracks');
['Kick','Snare','Clap','Hat','Open'].forEach((nm,ti)=>{
const tr_=document.createElement('div');
tr_.className='track';
const trackKey=['k','s','c','h','o'][ti];
tr_.dataset.track=trackKey;
// mute button
const muteBtn=document.createElement('button');
muteBtn.className='track-btn';
muteBtn.textContent='M';
muteBtn.title=`Mute ${nm}`;
muteBtn.setAttribute('aria-pressed','false');
muteBtn.style.minWidth='32px';muteBtn.style.minHeight='32px';muteBtn.style.padding='2px';muteBtn.style.fontSize='10px';
muteBtn.addEventListener('click',()=>toggleTrackMute(trackKey));
const name=document.createElement('div');
name.className='track-name';
name.textContent=nm;
const grid=document.createElement('div');
grid.className='steps-grid';
for(let i=0;i<16;i++){
const step=document.createElement('button');
step.className='step';
step.type='button';
step.setAttribute('aria-pressed','false');
step.setAttribute('role','switch');
step.setAttribute('aria-label',`${nm} step ${i+1}`);
step.dataset.track=trackKey;
step.dataset.step=i;
stepUiByIndex[i].push(step);
const velFill=document.createElement('div');
velFill.className='vel-fill';
step.appendChild(velFill);
const updateVelFill=()=>{
const dp=DRUM_PATTERNS[pat_.d];
if(!dp||!dp[trackKey])return;
const v=dp[trackKey][i];
velFill.style.height=v>0?Math.round(30+v*70)+'%':'0';
step.setAttribute('aria-pressed',v>0?'true':'false');
};
step.addEventListener('focus',()=>{st_.lastTrackKey=trackKey;});
step.addEventListener('click',e=>{
st_.lastTrackKey=trackKey;
pushHistory();
const dp=DRUM_PATTERNS[pat_.d];
if(!dp)return;
if(!dp[trackKey])return;
if(e.shiftKey){
const ratch=parseInt(step.dataset.ratchet||'1');
const newR=ratch===1?2:ratch===2?4:1;
step.dataset.ratchet=newR>1?newR:'';
seq_[trackKey][i].r=newR;
log(`${nm} step ${i+1} ratchet=${newR}`);
}else{
dp[trackKey][i]=dp[trackKey][i]>0?0:0.8;
updateVelFill();
}
});
step.addEventListener('contextmenu',e=>{
e.preventDefault();
showCtxMenu(e.clientX,e.clientY,[
{label:'Probability 25%',action:()=>{seq_[trackKey][i].p=25;step.dataset.prob='25'}},
{label:'Probability 50%',action:()=>{seq_[trackKey][i].p=50;step.dataset.prob='50'}},
{label:'Probability 75%',action:()=>{seq_[trackKey][i].p=75;step.dataset.prob='75'}},
{label:'Probability 100%',action:()=>{seq_[trackKey][i].p=100;step.dataset.prob=''}},
{label:'Velocity Low (40%)',action:()=>{const dp=DRUM_PATTERNS[pat_.d];if(dp&&dp[trackKey]&&dp[trackKey][i]>0){dp[trackKey][i]=0.4;updateVelFill();}}},
{label:'Velocity Mid (70%)',action:()=>{const dp=DRUM_PATTERNS[pat_.d];if(dp&&dp[trackKey]&&dp[trackKey][i]>0){dp[trackKey][i]=0.7;updateVelFill();}}},
{label:'Velocity Full',action:()=>{const dp=DRUM_PATTERNS[pat_.d];if(dp&&dp[trackKey]&&dp[trackKey][i]>0){dp[trackKey][i]=1.0;updateVelFill();}}},
]);
});
step.addEventListener('mousedown',event=>{
if(event.shiftKey){
st_.paintMode=true;
st_.paintState=step.getAttribute('aria-pressed')!=='true';
}
});
step.addEventListener('mouseenter',()=>{
if(st_.paintMode){
pushHistory();
const dp=DRUM_PATTERNS[pat_.d];
dp[trackKey][i]=st_.paintState?0.8:0;
updateVelFill();
}
});
grid.appendChild(step);
}
tr_.appendChild(muteBtn);
tr_.appendChild(name);
tr_.appendChild(grid);
tracks_c.appendChild(tr_);
});
document.addEventListener('mouseup',()=>{st_.paintMode=false});
const vu=$id('vu');
for(let i=0;i<20;i++){
const bar=document.createElement('div');
bar.className='vu-bar';
vu.appendChild(bar);
}
let fxUpdateFrame=null;
const scheduleFXUpdate=()=>{
if(fxUpdateFrame!==null)return;
fxUpdateFrame=requestAnimationFrame(()=>{
fxUpdateFrame=null;
applyFX();
});
};
['bpm','swing','drive','tape','comp','width','reverb','delay','filter','wobble','vinyl','crackle','drum-vol','bass-vol','keys-vol','pads-vol','master-vol'].forEach(id=>{
const inp=$id(id),out=$id(`${id}-o`);
const handler=()=>{
const v=Number(inp.value);
out.textContent=Math.round(v);
if(id==='bpm')aud_.bpm=v;
else if(id==='swing')aud_.swing=v;
else if(id==='drive')aud_.drive=v;
else if(id==='tape')aud_.tape=v;
else if(id==='comp')aud_.comp=v;
else if(id==='width')aud_.width=v;
else if(id==='reverb')aud_.reverb=v;
else if(id==='delay')aud_.delay=v;
else if(id==='filter')aud_.filter=v;
else if(id==='wobble')aud_.wobble=v;
else if(id==='vinyl')aud_.vinyl=v;
else if(id==='crackle')aud_.crackle=v;
else if(id==='drum-vol')mix_.drum=v;
else if(id==='bass-vol')mix_.bass=v;
else if(id==='keys-vol')mix_.keys=v;
else if(id==='pads-vol')mix_.pads=v;
else if(id==='master-vol')mix_.master=v;
scheduleFXUpdate();
};
inp.addEventListener('input',handler,{passive:true});
});
}

function showCtxMenu(x,y,items){
const menu=$id('ctx-menu');
menu.replaceChildren();
menu.style.display='block';
menu.style.left=`${x}px`;
menu.style.top=`${y}px`;
items.forEach(it=>{
const btn=document.createElement('button');
btn.textContent=it.label;
btn.addEventListener('click',()=>{
it.action();
menu.style.display='none';
});
menu.appendChild(btn);
});
const hide=()=>{menu.style.display='none';document.removeEventListener('click',hide)};
setTimeout(()=>document.addEventListener('click',hide),10);
}

function toggleTheme(){
st_.theme=st_.theme==='dark'?'light':'dark';
document.documentElement.setAttribute('data-theme',st_.theme);
refreshVizColors();
writeStorage('rg69_theme',st_.theme);
log(`theme: ${st_.theme}`);
}

function tapTempo(){
const now=Date.now();
st_.tapTimes.push(now);
if(st_.tapTimes.length>4)st_.tapTimes.shift();
if(st_.tapTimes.length>=2){
const intervals=[];
for(let i=1;i<st_.tapTimes.length;i++){
intervals.push(st_.tapTimes[i]-st_.tapTimes[i-1]);
}
const avgInterval=intervals.reduce((a,b)=>a+b,0)/intervals.length;
const bpm=60000/avgInterval;
if(bpm>=60&&bpm<=170){
aud_.bpm=bpm;
$id('bpm').value=bpm;
$id('bpm-o').textContent=Math.round(bpm);
log(`tap tempo: ${Math.round(bpm)} BPM`,"k");
}
}
setTimeout(()=>{st_.tapTimes=[]},2000);
}

const encodeState=()=>{
try{return btoa(JSON.stringify({pat_,aud_,mix_}));}catch(e){log('encode failed: '+e.message,'e');return '';}
};
const decodeState=h=>{
try{
const s=JSON.parse(atob(h));
if(s.pat_)Object.assign(pat_,s.pat_);
if(s.aud_)Object.assign(aud_,s.aud_);
if(s.mix_)Object.assign(mix_,s.mix_);
syncUIFromState();
log('state loaded from URL','k');
return true;
}catch(e){log('decode failed: '+e.message,'e');return false;}
};
const shareURL=()=>{
const hash=encodeState();
if(!hash)return;
const url=location.origin+location.pathname+'#'+hash;
navigator.clipboard.writeText(url).then(()=>log('URL copied to clipboard','k')).catch(()=>log('copy failed','e'));
};

function toggleTrackMute(trackKey){
const row=document.querySelector(`.track[data-track="${trackKey}"]`);
if(!row)return;
const muted=!Boolean(st_.muteState[trackKey]);
st_.muteState[trackKey]=muted?1:0;
row.classList.toggle('muted',muted);
const button=row.querySelector('.track-btn');
if(button){
button.setAttribute('aria-pressed',muted?'true':'false');
button.style.background=muted?'var(--dng)':'';
button.style.color=muted?'#fff':'';
}
st_.lastTrackKey=trackKey;
log(`${trackKey} ${muted?'muted':'unmuted'}`);
}

function handleKeys(e){
const target=e.target;
const tag=target?.tagName?.toUpperCase();
const textEntry=target?.isContentEditable||tag==='TEXTAREA'||tag==='SELECT'||
(tag==='INPUT'&&['text','search','email','url','password'].includes(target.type));
if(textEntry)return;
const k=e.key.toLowerCase();
const welcome=$id('welcome');
const welcomeOpen=welcome&&getComputedStyle(welcome).display!=='none';
if(welcomeOpen){
if((k===' '||k==='enter'||k==='p')&&!e.repeat){
e.preventDefault();
$id('welcome-start').click();
return;
}
const supportedShortcut=['s','r','e','l','t','m'].includes(k)||
((k==='z'||k==='c'||k==='v')&&(e.ctrlKey||e.metaKey));
if(!supportedShortcut)return;
dismissWelcome();
}
if(k===' '&&target?.matches?.('button,a,summary,[role="button"]'))return;
if(k===' '&&!e.repeat){e.preventDefault();$id('play').click();}
else if(k==='p'&&!e.repeat){e.preventDefault();$id('play').click();}
else if(k==='s'&&!e.repeat){e.preventDefault();$id('stop').click();}
else if(k==='r'&&!e.repeat){e.preventDefault();$id('random').click();}
else if(k==='e'&&!e.repeat){e.preventDefault();$id('export').click();}
else if(k==='l'&&!e.repeat){e.preventDefault();$id('layout').click();}
else if(k==='t'&&!e.repeat){e.preventDefault();$id('theme').click();}
else if(k==='m'&&!e.repeat){e.preventDefault();toggleTrackMute(target?.closest?.('.track')?.dataset.track||st_.lastTrackKey||'k');}
else if(k==='escape'){e.preventDefault();$id('panic').click();}
else if(k==='z'&&(e.ctrlKey||e.metaKey)){e.preventDefault();if(e.shiftKey)redo();else undo();}
else if(k==='c'&&(e.ctrlKey||e.metaKey)){e.preventDefault();navigator.clipboard.writeText(JSON.stringify({pat:pat_,seq:seq_,aud:aud_,mix:mix_}));log('copied to clipboard');}
else if(k==='v'&&(e.ctrlKey||e.metaKey)){e.preventDefault();navigator.clipboard.readText().then(t=>{try{const d=JSON.parse(t);if(d.pat&&d.seq){pushHistory();pat_=d.pat;seq_=d.seq;if(d.aud)aud_=d.aud;if(d.mix)mix_=d.mix;syncUIFromState();log('pasted from clipboard',"k")}}catch(err){log('paste failed: invalid data',"e")}});}
}

// One gesture is enough: boot the engine if it is not running yet, then start
// the transport. The welcome gate and the play button both land here, so the
// first click plays music instead of only arming the engine.
function startToneFromGesture(){const context=Tone.getContext();if(location.origin==="null")context.clockSource="timeout";return Tone.start();}

async function startPlayback(activationPromise){
if(!st_.started){
if(!st_.booting){
st_.booting=(async()=>{
await initAudio(activationPromise);
applyFX();
st_.started=true;
claimOwner();
st_.heartbeat=setInterval(keepOwner,1800);
pushHistory();
})();
}
try{await st_.booting;}catch(e){st_.booting=null;throw e;}
st_.booting=null;
}else{
// Called again inside a user gesture (the welcome gate after a blocked
// autoplay): Tone.start() resumes the suspended context here.
await (activationPromise||Tone.start());
}
st_.playing=true;
if(!st_.rafId)st_.rafId=requestAnimationFrame(updateVisuals);
st_.idx=-1;
Tone.Transport.bpm.value=aud_.bpm;
if(!st_.transportId)st_.transportId=Tone.Transport.scheduleRepeat(scheduleLoop,"16n");
Tone.Transport.start();
st('playing');
$id('play').textContent='⏸ Pause';
log('playback started','k');
}

$id('welcome-start').addEventListener('click',async()=>{
try{
dismissWelcome();
st('starting audio…');
const activationPromise=startToneFromGesture();
await startPlayback(activationPromise);
log('engine started via welcome gate','k');
}catch(error){
st_.playing=false;
st('audio startup failed — check browser permissions');
log(`audio startup failed: ${error.message}`,'e');
}
});
$id('play').addEventListener('click',async()=>{
if(!st_.playing){
try{const activationPromise=startToneFromGesture();await startPlayback(activationPromise);}catch(error){st_.playing=false;st('audio startup failed');log(`audio startup failed: ${error.message}`,'e');}
}else{
Tone.Transport.pause();
st_.playing=false;
st('paused');
$id('play').textContent='▶ Play';
log('playback paused');
}
});
$id('stop').addEventListener('click',()=>{
st_.playing=false;
if(st_.started){Tone.Transport.stop();Tone.Transport.cancel();}st_.transportId=null;
st_.idx=-1;
st_.barCount=0;
const posEl=$id('pos-display');if(posEl)posEl.textContent='●';
document.querySelectorAll('.step').forEach(el=>el.classList.remove('playing'));
st('stopped');
log("playback stopped");
});
$id('random').addEventListener('click',randomize);
$id('export').addEventListener('click',exportWAV);
$id('record').addEventListener('click',toggleRecord);
$id('layout').addEventListener('click',()=>{
st_.layoutIdx=(st_.layoutIdx+1)%51;
const cfg=st_.layoutIdx===50?finalBlend:layouts[st_.layoutIdx];
const nm=cfg.id==='final'?'final blend':`layout ${cfg.id}`;
applyLayout(cfg,nm);
log(`layout: ${nm}`);
});
$id('theme').addEventListener('click',toggleTheme);
$id('tap').addEventListener('click',tapTempo);
$id('steps').addEventListener('click',()=>{
st_.stepCount=st_.stepCount===16?8:16;
$id('steps').textContent=`⟨${st_.stepCount}⟩ Steps`;
document.querySelectorAll('.step').forEach((el,i)=>el.classList.toggle('inactive',i%16>=st_.stepCount));
log(`steps: ${st_.stepCount}`);
});
$id('undobtn').addEventListener('click',undo);
// lock buttons
document.querySelectorAll('.lock-btn').forEach(btn=>{
btn.addEventListener('click',()=>{
btn.classList.toggle('locked');
btn.textContent=btn.classList.contains('locked')?'🔒':'🔓';
});
});
// pattern change → update root display
['drum-pat','bass-pat','keys-pat','pads-pat'].forEach(id=>{
$id(id).addEventListener('change',updateRootDisplay);
});
updateRootDisplay();
$id('panic').addEventListener('click',()=>{
st_.playing=false;
clearTimeout(st_.timer);
clearInterval(st_.heartbeat);
cancelAnimationFrame(st_.rafId);
st_.rafId=null;
releaseOwner();
if(st_.started){Tone.Transport.stop();Tone.Transport.cancel();}
st_.transportId=null;
[kickN,kickSub,kickClk,kickBody,snareN,snareRng,clapN,hatN,openN,bassN,bassSub,keysN,padsN].forEach(s=>{
s?.releaseAll?.();
});
st('killed');
log("panic: all stopped","e");
});

document.addEventListener('keydown',handleKeys);
$id('shareBtn').addEventListener('click',shareURL);
if(location.hash.length>1){try{decodeState(location.hash.slice(1));}catch(e){}}
document.body.addEventListener('dblclick',tapTempo);

if(bc){
bc.addEventListener('message',e=>{
if(e.data.t==='stop'&&e.data.to===selfId){
st_.playing=false;
clearTimeout(st_.timer);
log("remote stop","e");
}
});
}

const savedTheme=readStorage('rg69_theme')||'dark';
st_.theme=savedTheme;
document.documentElement.setAttribute('data-theme',st_.theme);
refreshVizColors();

applyLayout(finalBlend,'final blend');
resizeVizCanvas();
buildUI();
// Reflect this page load's random playable style before the first paint.
syncUIFromState();
log(`RG-69 ready — ${bootStyle.n} · type help in terminal`,"k");

// Audio is deliberately gesture-gated. Do not call Tone.start() or touch
// Tone.Transport during page initialization; Chrome may create/resume the
// AudioContext only from the welcome or Play button gesture.

// ─── terminal ───────────────────────────────────────────────────────────────
const TERM_CMDS=[
'play / stop / pause / panic / undo / redo / random / export / record / share / theme / tap / layout',
'bpm <60-170>  swing/drive/tape/comp/width/reverb/delay/filter/wobble/vinyl/crackle <0-100>',
'steps <8|16>  mute/unmute <k|s|c|h|o>',
'style <name>  mood <name>',
'ls [styles|moods|patterns]  status  clear',
];
const termHist=[];
let termHistIdx=-1;

function execCmd(raw){
const line=raw.trim();
if(!line)return;
termHist.unshift(line);
termHistIdx=-1;
log(`$ ${line}`, "c");
const [cmd,...args]=line.toLowerCase().split(/\s+/);
const n=parseFloat(args[0]);
const PARAMS={swing:1,drive:1,tape:1,comp:1,width:1,reverb:1,delay:1,filter:1,wobble:1,vinyl:1,crackle:1};

switch(cmd){
case'help':case'?':TERM_CMDS.forEach(l=>log(l));break;
case'clear':case'cls':$id('trace').replaceChildren();break;
case'play':case'p':$id('play').click();break;
case'stop':$id('stop').click();break;
case'pause':if(st_.playing)$id('play').click();break;
case'panic':$id('panic').click();break;
case'undo':undo();break;
case'redo':redo();break;
case'random':case'rnd':randomize();break;
case'export':case'wav':exportWAV();break;
case'record':case'rec':toggleRecord();break;
case'theme':toggleTheme();break;
case'tap':tapTempo();break;
case'share':shareURL();break;
case'layout':$id('layout').click();break;
case'bpm':
if(!isNaN(n)&&n>=60&&n<=170){aud_.bpm=n;$id('bpm').value=n;$id('bpm-o').textContent=Math.round(n);applyFX();log(`bpm → ${Math.round(n)}`,'k');}
else log('usage: bpm <60-170>','e');
break;
case'steps':{
const s=parseInt(args[0]);
if(s===8||s===16){st_.stepCount=s;$id('steps').textContent=`⟨${s}⟩`;document.querySelectorAll('.step').forEach((el,i)=>el.classList.toggle('inactive',i%16>=s));log(`steps → ${s}`,'k');}
else log('usage: steps <8|16>','e');
break;}
case'style':{
const nm=args.join(' ');
const match=STYLES.find(s=>s.n.toLowerCase()===nm||s.n.toLowerCase().replace(/\s+/g,'-')===nm.replace(/\s+/g,'-'));
if(match){pushHistory();pat_.d=match.d;pat_.b=match.b;pat_.k=match.k;pat_.p=match.p;aud_.bpm=match.bpm[0]+Math.random()*(match.bpm[1]-match.bpm[0]);aud_.swing=match.sw[0]+Math.random()*(match.sw[1]-match.sw[0]);aud_.drive=match.dr[0]+Math.random()*(match.dr[1]-match.dr[0]);aud_.tape=match.tm[0]+Math.random()*(match.tm[1]-match.tm[0]);syncUIFromState();log(`style → ${match.n}`,'k');}
else log(`not found: ${nm}  (try: ls styles)`,'e');
break;}
case'mood':{
const m=M[args[0]];
if(m){applyMood(m);log(`mood → ${args[0]}`,'k');}
else log(`not found: ${args[0]}  (try: ls moods)`,'e');
break;}
case'mute':case'unmute':{
const t=args[0];
if(['k','s','c','h','o'].includes(t)){
const mute=cmd==='mute';
st_.muteState[t]=mute?1:0;
const row=[...document.querySelectorAll('.track')].find(el=>el.querySelector(`.step[data-track="${t}"]`));
if(row)row.classList.toggle('muted',mute);
log(`${cmd} → ${t}`,'k');
}else log(`usage: ${cmd} <k|s|c|h|o>`,'e');
break;}
case'ls':
if(args[0]==='styles')log(STYLES.map(s=>s.n).join(' · '));
else if(args[0]==='moods')log(Object.keys(M).join(' · '));
else if(args[0]==='patterns'){log('drums: '+Object.keys(DRUM_PATTERNS).join(' '));log('bass: '+Object.keys(BASS_PATS).join(' '));log('keys: '+Object.keys(KEYS_PATS).join(' '));log('pads: '+Object.keys(PAD_PATS).join(' '));}
else log('ls [styles|moods|patterns]');
break;
case'status':case'info':
log(`bpm:${Math.round(aud_.bpm)} swing:${Math.round(aud_.swing)} steps:${st_.stepCount} playing:${st_.playing}`);
log(`d:${pat_.d}  b:${pat_.b}  k:${pat_.k}  p:${pat_.p}`);
break;
default:
if(PARAMS[cmd]){
if(!isNaN(n)&&n>=0&&n<=100){aud_[cmd]=n;const el=$id(cmd);if(el)el.value=n;const out=$id(`${cmd}-o`);if(out)out.textContent=Math.round(n);applyFX();log(`${cmd} → ${Math.round(n)}`,'k');}
else log(`usage: ${cmd} <0-100>`,'e');
}else{log(`unknown: ${cmd}  (help for commands)`,'e');}
}
}

$id('term-input').addEventListener('keydown',e=>{
if(e.key==='Enter'){const v=$id('term-input').value;$id('term-input').value='';execCmd(v);}
else if(e.key==='ArrowUp'){e.preventDefault();if(termHistIdx<termHist.length-1){termHistIdx++;$id('term-input').value=termHist[termHistIdx];}}
else if(e.key==='ArrowDown'){e.preventDefault();if(termHistIdx>0){termHistIdx--;$id('term-input').value=termHist[termHistIdx];}else{termHistIdx=-1;$id('term-input').value='';}}
});
// ────────────────────────────────────────────────────────────────────────────

// serviceWorker intentionally omitted — sw.js not present
