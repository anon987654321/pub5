import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Run the real inline event compiler, without browser or audio mocks.
const html=readFileSync(new URL('../../dilla/rg69/rg69.html',import.meta.url),'utf8');
const extract=(a,b)=>{const i=html.indexOf(a),j=html.indexOf(b,i+1);assert(i>=0&&j>i,a);return html.slice(i,j);};
const script=html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
new Function(script);
const ranges=[["const DRUM_PATTERNS=","const STYLES="],["const LANES=","const tpCache="],["function swingOffsetSeconds(","function scheduleLoop("],["function detectSlices(","async function loadSample("],["function midiBytes(","function exportMIDI("]];
const fixture="\nconst tp=(a,t)=>Array.isArray(a)?a:Array(t||16).fill(a);\nconst tpP=object=>Object.fromEntries(Object.entries(object).map(([key,value])=>[key,tp(value)]));\nconst crypto={getRandomValues:a=>(a[0]=42,a)};\nconst deepClone=x=>JSON.parse(JSON.stringify(x));\nconst syncUIFromState=()=>{};\nconst st_={started:false,stepCount:16,bank:0,laneLengths:{},muteState:{}};\nconst aud_={bpm:96,swing:35,pocket:68},mix_={master:75},pat_={d:\"basic\",b:Object.keys(BASS_PATS)[0],k:Object.keys(KEYS_PATS)[0],p:Object.keys(PAD_PATS)[0]};\nconst seq_=Object.fromEntries(LANES.map(l=>[l,Array.from({length:64},(_,i)=>({v:.9,t:i%2?25:-25,p:100,r:4,g:1,cond:1,pitch:0}))]));\nconst rg69AudioProfile={notes:{kick:60,kickSub:30,kickBody:65,snareRing:180,hat:9000,open:6000}};\n";
const checks="\nlet cases=0,steps=0,events=0;\nfor(const bpm of [60,170])for(const count of [8,16,32,64])for(const swing of [0,100])for(const pocket of [0,100]){\nconst take=session();take.steps=count;take.aud={bpm,swing,pocket};take.lengths={h:5,s:7};\ntake.drums[take.pat.d]=Object.fromEntries(DRUM_LANES.map(l=>[l,Array(16).fill(.9)]));\nconst sixteenth=60/bpm/4,last={};\nfor(let i=0;i<256;i++){\nconst args=[i%count,.05+i*sixteenth,{session:take,tick:i,stepCount:count,muteMap:{},applyProb:true,applyRatchet:true,applyTranspose:true,addSwing:true,sixteenth}];\nconst result=compileStep(...args);\nassert(JSON.stringify(result)===JSON.stringify(compileStep(...args)),\"seed mismatch\");\nfor(let j=0;j<result.length;j++){\nconst e=result[j];\nassert(e.args.length===(NOISE_VOICES.has(e.voice)?3:4),\"argument count\");\nassert(Number.isFinite(e.time)&&e.time>=0,\"invalid time\");\nassert(j===0||e.time>=result[j-1].time,\"event order\");\nassert(e.time>=(last[e.voice]??0)-1e-9,\"voice order \"+e.voice);\nlast[e.voice]=e.time;events++;\n}\nsteps++;\n}\ncases++;\n}\nconst take=session();take.drums[take.pat.d]=Object.fromEntries(DRUM_LANES.map(l=>[l,Array(16).fill(1)]));\ntake.seq.k[0].p=0;take.seq.s[0].p=100;\nconst muted=compileStep(0,.05,{session:take,tick:0,stepCount:16,muteMap:{s:1},applyProb:true,applyRatchet:true,addSwing:true});\nassert(!muted.some(e=>[\"kick\",\"kickSub\",\"kickClk\",\"kickBody\",\"snare\",\"snareRng\"].includes(e.voice)),\"mute/probability\");\nconst midi=midiBytes(take,1),view=new DataView(midi.buffer);\nassert(String.fromCharCode(...midi.slice(0,4))===\"MThd\"&&String.fromCharCode(...midi.slice(14,18))===\"MTrk\",\"MIDI header\");\nassert(view.getUint32(18)===midi.length-22,\"MIDI length\");\nconst original=session();seq_.k[0].hit=.22;restoreSession(original);\nassert(seq_.k[0].hit===undefined,\"session override restoration\");\nconst pcm=new Float32Array(8000);for(let i=500;i<pcm.length;i+=1000)pcm.fill(.8,i,i+30);\nconst buffer={duration:1,sampleRate:8000,getChannelData:()=>pcm};\nassert(detectSlices(buffer,\"equal\").length===16,\"equal slices\");\nassert(detectSlices(buffer).length>=4,\"transient slices\");\nreturn {cases,steps,events,seed:\"deterministic\",midi:\"valid header and track length\",session:\"override restoration\",samples:\"slice detection passed\"};\n";
const sources=ranges.map(([a,b])=>extract(a,b));
const prefix=fixture.slice(0,fixture.indexOf('const aud_='));
const state=fixture.slice(fixture.indexOf('const aud_='));
const run=new Function('assert',prefix+sources[0]+sources[1]+state+sources.slice(2).join('\n')+checks);
console.log(JSON.stringify(run(assert),null,2));

const clockSource=extract("const audioTime=()=>","let stepUiByIndex=");
const clockTest=new Function("assert",clockSource+`
let now=0,callback=null,steps=0,failures=0;
const st_={playing:true,idx:-1,tick:-1,stepCount:16},aud_={bpm:120};
const Tone={getContext:()=>({rawContext:{currentTime:now}})};
const setTimeout=fn=>(callback=fn,1),clearTimeout=()=>{callback=null;};
const log=()=>{failures++},st=()=>{},console={warn(){}},$id=()=>null;
const scheduleLoop=time=>{steps++;if(steps===1)throw Error("synthetic voice failure");st_.idx=(st_.idx+1)%16;st_.tick++;};
startClock();assert(callback&&failures===1,"clock must survive first-step failure");
for(let i=0;i<120;i++){now+=.02;callback();}
assert(steps>=18&&steps<=22,"clock must advance at 120 BPM");
const before=steps;now+=20;callback();assert(steps-before<=4,"late clock must not flood audio");
const stale=callback;pauseClock();stale();assert(callback===null,"paused clock cannot reschedule");
st_.playing=true;startClock();assert(callback,"restart must arm clock");
return {clock:"passed",steps,failures};
`);
console.log(JSON.stringify(clockTest(assert),null,2));

const profileSource=extract("const httpPage=","function createToneInstruments");
const loadProfile=new Function("location","fetch","let rg69AudioProfile={name:'embedded'},rg69AudioProfileLocked=false;const log=()=>{},resolveRG69AudioProfile=x=>x;"+profileSource+"\nreturn rg69AudioProfileReady;");
const origins=[["file:","file://",0],["file:","null",0],["data:","null",0],["about:","null",0],["https:","null",0],["http:","http://localhost",1],["https:","https://example.com",1]];
for(const [protocol,origin,expected] of origins){
let calls=0;
const profile=await loadProfile({protocol,origin},()=>{calls++;return Promise.resolve({ok:true,json:async()=>({name:"catalogue"})});});
assert(calls===expected,"unexpected fetch "+protocol+" "+origin);
assert(profile.name===(expected?"catalogue":"embedded"),"incorrect profile");
}
console.log("profile origin checks: "+origins.length);

 // Strict graph mock: reject undefined instrument and connection endpoints.
const graphRanges=[["const PARAMS=","window.rg69ConsoleSink="],["const RG69_AUDIO_FALLBACK=","function resolveRG69AudioProfile"],["function createDrumBank(","const DRUM_PATTERNS="],["function createDefaultFX(","const DENSITIES="],["function createAudioGraph(","function applyFX("]];
const graphFixture=`
const edges=[];
const param=()=>({audioParam:true,value:0,rampTo(){},setValueAtTime(){},linearRampToValueAtTime(){}});
class Node {
constructor(){for(const key of ["gain","wet","frequency","detune","volume","Q","attack","ratio","width","threshold","knee","release","feedback","delayTime","pan","playbackRate"])this[key]=param();this.ready=Promise.resolve();}
connect(to){assert(to instanceof Node||to?.audioParam===true,"undefined or invalid connection destination");edges.push([this,to]);return this;}
disconnect(){}
start(){return this;}
stop(){return this;}
triggerAttackRelease(){}
}
const raw={sampleRate:8000,currentTime:0,destination:new Node(),createGain:()=>new Node(),createStereoPanner:()=>new Node(),createDynamicsCompressor:()=>new Node(),createBufferSource:()=>new Node(),createBuffer:(channels,length)=>({getChannelData:()=>new Float32Array(length)})};
const Tone=Object.fromEntries("Gain Filter Distortion Compressor StereoWidener Limiter Reverb FeedbackDelay Noise LFO Chebyshev Chorus Tremolo Panner Synth MonoSynth FMSynth PolySynth".split(" ").map(name=>[name,Node]));
Object.assign(Tone,{getContext:()=>({rawContext:raw}),mtof:n=>440*2**((n-69)/12),connect:(from,to)=>from.connect(to)});
const log=()=>{};
`;
const graphCheck=`
const rg69AudioProfile=finalizeRG69AudioProfile(RG69_AUDIO_FALLBACK);
const aud={bpm:150,drive:90,filter:80,comp:60,width:50,delay:20,tape:5,reverb:20,vinyl:0,crackle:0,wobble:0};
const mix={drum:80,bass:70,keys:60,pads:50,master:75};
const g=createAudioGraph(aud,mix,null),offline=createAudioGraph(aud,mix,null,{offline:true,duration:8});
const expected=["kick","kickSub","kickClk","kickBody","snare","snareRng","clap","hat","open","bass","bassSub","keys","pads"];
for(const graph of [g,offline]){
assert(JSON.stringify(Object.keys(graph.instruments).sort())===JSON.stringify(expected.slice().sort()),"instrument registry disagrees with scheduler");
for(const name of expected)assert(typeof graph.instruments[name].triggerAttackRelease==="function","missing "+name);
}
return {graphs:2,voices:expected.length,connections:edges.length};
`;
const graphResult=new Function("assert",graphFixture+graphRanges.map(([a,b])=>extract(a,b)).join("\n")+graphCheck)(assert);
console.log(JSON.stringify(graphResult,null,2));
