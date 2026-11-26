/* MASTER pixel-mask profile catalogue.
 * A bounded implicit surface sampler morphs the existing face point field; no second renderer,
 * bitmap, connected mesh, or downloaded asset is introduced. Cultural labels
 * identify reference families, not claims of ceremonial authenticity.
 */
(() => {
  "use strict";

  // Original concept studies, ordered as the approved 4 × 4 sheet, then five individual studies.
  const PROFILES = Object.freeze([
    { id: "folded-seed", name: "Folded seed", solid: [[-0.07,0.13,-0.05,0.46,0.42,0.36,-0.48],[0.1,-0.2,0.08,0.34,0.29,0.3,0.35]], voids: [[-0.225,0.1,0,0.17,0.16,0,-0.4,2,0.15],[0.2,0.14,0,0.16,0.22,0,0.45,2,0.18],[0.065,-0.28,0,0.14,0.095,0,0.2,2,0.1]] },
    { id: "block-portal", name: "Block portal", solid: [[0,0.05,0,0.43,0.49,0.35,0,5],[0,-0.23,0.04,0.32,0.26,0.28,0,4]], voids: [[-0.19,0.1,0,0.15,0.22,0,0,4,0.12],[0.19,0.1,0,0.15,0.22,0,0,4,0.16],[0,-0.27,0,0.17,0.1,0,0,4,0.2]] },
    { id: "trefoil", name: "Trefoil", solid: [[-0.22,0.11,-0.075,0.29,0.39,0.3,-0.48],[0.23,0.065,0.05,0.3,0.33,0.32,0.52],[0.015,-0.24,0.09,0.3,0.27,0.27]], voids: [[-0.21,0.15,0,0.16,0.2,0,-0.4,2,0.2],[0.24,0.09,0,0.16,0.15,0,0.4,2,0.16],[0.025,-0.255,0,0.15,0.09,0,0,2,0.12]] },
    { id: "stacked-fins", name: "Stacked fins", solid: [[0,0.3,0,0.51,0.15,0.31,-0.12],[0,0.02,0,0.43,0.15,0.34,0.16],[0.05,-0.28,0,0.34,0.18,0.26,-0.12],[0,0,-0.08,0.14,0.47,0.2]], voids: [[-0.22,0.12,0.18,0.2,0.1,0.35],[0.21,-0.12,0.15,0.17,0.1,0.35]] },
    { id: "paired-lobes", name: "Paired lobes", solid: [[-0.23,0.06,-0.065,0.32,0.44,0.36,-0.35],[0.22,0.08,0.06,0.32,0.42,0.32,0.38],[0,-0.27,0.09,0.26,0.25,0.25]], voids: [[-0.24,0.04,0,0.18,0.26,0,-0.25,2,0.18],[0.23,0.1,0,0.18,0.25,0,0.25,2,0.15],[0,-0.28,0.25,0.11,0.09,0.35]] },
    { id: "yoke", name: "Yoke", solid: [[-0.26,0.19,-0.045,0.32,0.25,0.27,-0.38],[0.25,0.18,0.055,0.32,0.25,0.3,0.38],[0,-0.14,-0.045,0.24,0.4,0.29]], voids: [[-0.22,0.19,0,0.19,0.12,0,-0.3,2,0.12],[0.24,0.18,0,0.19,0.13,0,0.3,2,0.16],[0,-0.18,0,0.14,0.19,0,0,2,0.2]] },
    { id: "porous-orb", name: "Porous orb", solid: [[0,0,-0.045,0.47,0.48,0.45],[0.1,0.16,0.025,0.38,0.37,0.39]], voids: [[-0.21,0.16,0,0.17,0.19,0,-0.4,2,0.12],[0.22,0.12,0,0.16,0.21,0,0.2,2,0.16],[0.03,-0.23,0,0.2,0.14,0,0,2,0.2],[0.05,0.39,-0.12,0.12,0.13,0.29],[-0.35,-0.2,0,0.12,0.13,0.24]] },
    { id: "crescent", name: "Crescent", solid: [[0,0.1,-0.025,0.49,0.43,0.35,-0.38],[0.09,-0.29,0.1,0.26,0.22,0.28,0.55]], voids: [[-0.09,0.04,0,0.35,0.28,0,-0.42,2,0.22],[0.02,-0.19,0.21,0.15,0.13,0.33]] },
    { id: "fragment", name: "Fragment", solid: [[-0.22,0.1,-0.045,0.27,0.31,0.29,-0.3],[0.21,0.12,0.065,0.25,0.32,0.27,0.4],[0.01,-0.22,-0.025,0.22,0.23,0.25]], voids: [[-0.22,0.1,0,0.15,0.14,0,0,2,0.12],[0.21,0.14,0,0.14,0.15,0,0,2,0.16],[0.01,-0.22,0.2,0.12,0.09,0.35]] },
    { id: "twin-bulb", name: "Twin bulb", solid: [[-0.22,0.1,-0.045,0.3,0.37,0.35,-0.34],[0.21,0.12,0.055,0.33,0.36,0.37,0.34],[0,-0.22,-0.045,0.29,0.24,0.25]], voids: [[-0.18,0.07,0,0.13,0.16,0,0,2,0.12],[0.22,0.14,0,0.16,0.16,0,0,2,0.16],[0.02,-0.22,0.24,0.12,0.08,0.32]] },
    { id: "branching", name: "Branching", solid: [[0,0,-0.045,0.23,0.42,0.3],[-0.27,0.19,0.055,0.29,0.13,0.19,-0.55],[0.26,0.21,-0.045,0.29,0.13,0.19,0.55],[-0.23,-0.22,0.055,0.28,0.13,0.2,0.5],[0.23,-0.22,-0.045,0.28,0.13,0.2,-0.5]], voids: [[-0.14,0.07,0.18,0.1,0.15,0.38],[0.15,0.08,0.18,0.1,0.15,0.38]] },
    { id: "asymmetric-pocket", name: "Asymmetric pocket", solid: [[-0.13,0.05,-0.045,0.4,0.43,0.36,-0.35],[0.23,-0.08,0.055,0.3,0.34,0.32,0.4]], voids: [[-0.16,0.13,0,0.24,0.21,0,-0.4,2,0.12],[0.27,-0.08,0,0.13,0.14,0,0.35,2,0.16]] },
    { id: "layered-cap", name: "Layered cap", solid: [[0,0.3,0,0.47,0.16,0.35,-0.08],[-0.1,0.02,0,0.43,0.16,0.29,0.2],[0.09,-0.24,0,0.35,0.17,0.27,-0.22],[0,0,-0.06,0.17,0.43,0.18]], voids: [[-0.16,0.14,0.19,0.17,0.1,0.35],[0.18,-0.08,0.18,0.17,0.1,0.37]] },
    { id: "double-ring", name: "Double ring", solid: [[-0.23,0.07,-0.085,0.33,0.42,0.34,-0.4],[0.23,0.06,0.09,0.34,0.42,0.34,0.4],[0.03,-0.22,0.02,0.26,0.26,0.29]], voids: [[-0.25,0.09,0,0.19,0.24,0,-0.3,2,0.2],[0.24,0.08,0,0.19,0.25,0,0.3,2,0.16],[0.02,-0.27,0,0.115,0.085,0,0,2,0.18]] },
    { id: "three-void-shell", name: "Three-void shell", solid: [[0,0.06,-0.04,0.48,0.47,0.39,-0.35],[0.09,-0.2,0.09,0.34,0.28,0.31,0.4]], voids: [[-0.2,0.2,0,0.21,0.18,0,-0.35,2,0.18],[0.235,0.04,0,0.165,0.21,0,0.4,2,0.2],[-0.03,-0.245,0,0.16,0.11,0,-0.25,2,0.15]] },
    { id: "dispersed", name: "Dispersed", solid: [[-0.21,0.07,-0.045,0.27,0.32,0.28,-0.3],[0.19,0.1,0.065,0.27,0.32,0.28,0.3],[0,-0.22,-0.045,0.22,0.22,0.23]], voids: [[-0.2,0.09,0,0.17,0.16,0,0,2,0.12],[0.19,0.11,0,0.17,0.16,0,0,2,0.16],[0,-0.22,0.2,0.12,0.09,0.36]] },
    { id: "round-knot", name: "Round knot", solid: [[-0.23,0.02,-0.045,0.3,0.4,0.36,-0.55],[0.21,0.15,0.055,0.34,0.38,0.34,0.55],[0.08,-0.22,-0.025,0.31,0.28,0.29,0.45]], voids: [[-0.22,0.03,0,0.17,0.22,0,-0.45,2,0.12],[0.23,0.17,0,0.2,0.19,0,0.45,2,0.16],[0.1,-0.25,0,0.16,0.1,0,0.25,2,0.2]] },
    { id: "oblique-hollow", name: "Oblique hollow", solid: [[-0.08,0.09,-0.045,0.46,0.44,0.4,-0.45],[0.2,-0.16,0.085,0.29,0.31,0.32,0.38]], voids: [[-0.16,0.17,0,0.28,0.25,0,-0.45,2,0.12],[0.24,-0.15,0.29,0.1,0.09,0.35]] },
    { id: "open-ribbon", name: "Open ribbon", solid: [[-0.24,0.06,-0.075,0.31,0.39,0.28,-0.4],[0.19,0.22,0.1,0.36,0.27,0.3,0.45],[0.1,-0.25,0.02,0.3,0.23,0.27,-0.45]], voids: [[-0.24,0.06,0,0.2,0.24,0,-0.4,2,0.18],[0.21,0.22,0,0.24,0.15,0,0.45,2,0.2],[0.06,-0.25,0,0.21,0.12,0,-0.45,2,0.12]] },
    { id: "eroded-monolith", name: "Eroded monolith", solid: [[-0.07,0.02,-0.045,0.43,0.51,0.41,-0.3,3],[0.24,-0.04,0.015,0.27,0.39,0.35,0.2,3]], voids: [[-0.2,0.12,0,0.24,0.17,0,-0.4,2,0.12],[0.23,0.04,0,0.13,0.23,0,0.2,2,0.16],[0.03,-0.28,0,0.18,0.15,0,0,2,0.2],[0.09,0.34,0.24,0.11,0.12,0.32]] },
    { id: "bifurcate", name: "Bifurcate", solid: [[-0.22,0.16,-0.045,0.32,0.32,0.29,-0.35],[0.23,0.16,0.055,0.34,0.33,0.32,0.35],[0.02,-0.23,-0.015,0.28,0.27,0.31]], voids: [[-0.22,0.13,0,0.21,0.19,0,-0.35,2,0.12],[0.23,0.15,0,0.23,0.2,0,0.35,2,0.16],[0.03,-0.27,0.25,0.14,0.08,0.38]] }
  ].map(profile => Object.freeze({ ...profile, family: "Original biomorphic sculpture", note: "Operator-approved concept; procedural interpretation, not a scan" })));

  const randomUnit = (index, salt) => {
    let n = Math.imul((index + 1) ^ Math.imul(salt + 1, 0x9e3779b1), 0x85ebca6b);
    n = Math.imul(n ^ (n >>> 13), 0xc2b2ae35);
    return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
  };

  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const descriptor = profile => ({
    kind: "custom", maskProfile: profile.id, label: profile.name, confidence: 1,
    sequence: profile.solid.map((_, i) => "mass-" + i),
    parts: profile.solid.map(([x,y,z,a,b,c], i) => ({
      key: "mass-" + i, primitive: "sphere", center: [x,y,z],
      size: [a,b,c].map(v => clamp(v,.06,.62))
    }))
  });

  // Superellipsoid fields and smooth CSG define a single continuous sculpture.
  // Cavities are spatial subtraction, never dark sprites or a projected stencil.
  const smoothMin = (a,b,k) => {
    const h = clamp(.5 + .5 * (b-a)/k,0,1);
    return b*(1-h)+a*h-k*h*(1-h);
  };
  function primitive([cx,cy,cz,a,b,c,angle=0,power=2,lean=0]) {
    const co = Math.cos(angle), si = Math.sin(angle), scale = c === 0 ? Math.min(a,b) : Math.min(a,b,c);
    return (x,y,z) => {
      x -= cx; y -= cy; z -= cz;
      // Zero axial radius encodes an open, oblique tunnel rather than a blind pocket.
      x += lean*z;
      const u = (co*x+si*y)/a, v = (-si*x+co*y)/b, w = c === 0 ? 0 : z/c;
      return ((Math.abs(u)**power+Math.abs(v)**power+Math.abs(w)**power)**(1/power)-1)*scale;
    };
  }
  const fields = new Map(PROFILES.map(profile => {
    const solids = profile.solid.map(primitive), voids = profile.voids.map(primitive);
    return [profile.id, (x,y,z) => {
      let d = solids[0](x,y,z);
      for (let i=1;i<solids.length;i++) d = smoothMin(d,solids[i](x,y,z),.085);
      for (const cut of voids) d = -smoothMin(-d,cut(x,y,z),.035);
      return d;
    }];
  }));

  function normalAt(id,x,y,z) {
    const field = fields.get(id);
    if (!field) return [0,0,1];
    const h = .002;
    const n = [field(x+h,y,z)-field(x-h,y,z),field(x,y+h,z)-field(x,y-h,z),field(x,y,z+h)-field(x,y,z-h)];
    const len = Math.hypot(...n);
    return len > 1e-10 ? n.map(v=>v/len) : [0,0,1];
  }

  // Marching tetrahedra build an invisible area table once per selected form.
  // Only sampled points reach WebGL; triangles never become a rendered mesh.
  const corners = [[0,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]];
  const tetrahedra = [[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]];
  let cachedId, cachedSurface;
  function surface(id) {
    if (cachedId === id) return cachedSurface;
    const field = fields.get(id);
    if (!field) return null;
    const n = 30, side = n+1, extent = .72, step = 2*extent/n;
    const index = (x,y,z) => (z*side+y)*side+x;
    const values = new Float32Array(side**3);
    for(let z=0;z<=n;z++) for(let y=0;y<=n;y++) for(let x=0;x<=n;x++)
      values[index(x,y,z)] = field(x*step-extent,y*step-extent,z*step-extent);
    const triangles = [], cumulative = [];
    let total=0;
    function triangle(a,b,c) {
      const u=b.map((v,i)=>v-a[i]), v=c.map((v,i)=>v-a[i]);
      const area=.5*Math.hypot(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]);
      if(area<1e-10) return;
      total+=area; triangles.push([a,b,c]); cumulative.push(total);
    }
    for(let z=0;z<n;z++) for(let y=0;y<n;y++) for(let x=0;x<n;x++) {
      const ds=corners.map(([a,b,c])=>values[index(x+a,y+b,z+c)]);
      if(ds.every(v=>v>=0)||ds.every(v=>v<0)) continue;
      const ps=corners.map(([a,b,c])=>[(x+a)*step-extent,(y+b)*step-extent,(z+c)*step-extent]);
      const edge=(a,b)=>ps[a].map((v,i)=>v+(ps[b][i]-v)*ds[a]/(ds[a]-ds[b]));
      for(const tet of tetrahedra) {
        const inside=tet.filter(i=>ds[i]<0), outside=tet.filter(i=>ds[i]>=0);
        if(!inside.length||!outside.length) continue;
        if(inside.length===1||outside.length===1) {
          const single=inside.length===1?inside:outside, rest=inside.length===1?outside:inside;
          triangle(...rest.map(i=>edge(single[0],i)));
        } else {
          const [a,b]=inside,[c,d]=outside;
          const p=edge(a,c),q=edge(a,d),r=edge(b,c),s=edge(b,d);
          triangle(p,q,r); triangle(q,s,r);
        }
      }
    }
    cachedId=id; cachedSurface={triangles,cumulative,total};
    return cachedSurface;
  }

  function candidate(mesh,index,id,interior) {
    const target=randomUnit(index,1)*mesh.total;
    let lo=0,hi=mesh.cumulative.length-1;
    while(lo<hi) { const mid=(lo+hi)>>>1; if(mesh.cumulative[mid]<target) lo=mid+1; else hi=mid; }
    const [a,b,c]=mesh.triangles[lo], u=Math.sqrt(randomUnit(index,2)), v=randomUnit(index,3);
    const wa=1-u,wb=u*(1-v),wc=u*v;
    const point = [a[0]*wa+b[0]*wb+c[0]*wc,a[1]*wa+b[1]*wb+c[1]*wc,a[2]*wa+b[2]*wb+c[2]*wc];
    if (!interior) return point;
    // A sparse inner stratum adds parallax, but cannot occupy a carved void.
    const normal = normalAt(id, ...point), field = fields.get(id);
    const depth = .025 + .075 * randomUnit(index,4);
    for (const fraction of [1,.5,.25]) {
      const inner = point.map((v,i)=>v-normal[i]*depth*fraction);
      if (field(...inner) < -.008) return inner;
    }
    return point;
  }

  // Progressive best-candidate sampling. A bounded spatial hash favours
  // separation without a quadratic all-pairs search or a visible lattice.
  // Every prefix is stable, independent of the requested device point count.
  let sampleId, points=[], buckets=new Map(), cellSize=0;
  const key=(x,y,z)=>((x+512)*1024+y+512)*1024+z+512;
  const cell=v=>Math.floor(v/cellSize);
  function insert(p) {
    const k=key(cell(p[0]),cell(p[1]),cell(p[2]));
    if(!buckets.has(k)) buckets.set(k,[]);
    buckets.get(k).push(p);
  }
  function separation(p, threshold) {
    const x=cell(p[0]),y=cell(p[1]),z=cell(p[2]);
    let best=cellSize*cellSize;
    for(let dz=-1;dz<=1;dz++) for(let dy=-1;dy<=1;dy++) for(let dx=-1;dx<=1;dx++) {
      const neighbours=buckets.get(key(x+dx,y+dy,z+dz));
      if(!neighbours) continue;
      for(const q of neighbours) {
        const a=p[0]-q[0],b=p[1]-q[1],c=p[2]-q[2];
        const distance=a*a+b*b+c*c;
        if(distance<=threshold) return distance;
        best=Math.min(best,distance);
      }
    }
    return best;
  }
  function sample(id,index) {
    if(!Number.isSafeInteger(index)||index<0||index>=262144) return null;
    const mesh=surface(id);
    if(!mesh?.triangles.length) return null;
    if(sampleId!==id) { sampleId=id; points=[]; buckets=new Map(); cellSize=0; }
    while(points.length<=index) {
      const n=points.length;
      const radius=Math.max(.004, Math.min(.32,Math.sqrt(mesh.total/Math.max(1,n))));
      const size=2**Math.ceil(Math.log2(radius));
      if(size!==cellSize) {
        cellSize=size; buckets.clear();
        for(const p of points) insert(p);
      }
      let best=null, score=-1;
      for(let j=0;j<8;j++) {
        const p=candidate(mesh,n*8+j,id,n%8===7), d=separation(p,score);
        if(d>score) { best=p; score=d; }
        if(score>=cellSize*cellSize) break;
      }
      points.push(best); insert(best);
    }
    return points[index].slice();
  }

  // These nonhuman forms have no mandatory anatomical mouth.
  function mouthGeometry() { return null; }

  function hash(value) {
    let h = 2166136261;
    for (const char of String(value)) h = Math.imul(h ^ char.charCodeAt(0), 16777619);
    return h >>> 0;
  }
  const ROTATION_PROFILE_IDS = Object.freeze(PROFILES.map(({ id }) => id));

  function profileIndex(id) {
    return PROFILES.findIndex((profile) => profile.id === String(id));
  }

  function conversationKey() {
    const explicit = window.MASTER_FACE_MASK_SESSION ||
      document.querySelector('meta[name="master-face-mask-session"]')?.content ||
      window.history?.state?.faceMaskSession;
    if (explicit != null && String(explicit)) return String(explicit);
    try {
      let session = sessionStorage.getItem("master.mask.session");
      if (!session) {
        session = String(Date.now()) + ":" + Math.random().toString(36).slice(2);
        sessionStorage.setItem("master.mask.session", session);
      }
      return session;
    } catch (_) {
      return location.pathname + location.search;
    }
  }

  function sourceFor(profile) {
    const direct = window.MASTER_FACE_MASK_ENTRY;
    if (direct && String(direct.particle_profile || "") === profile.id) return direct;
    const catalog = Array.isArray(window.MASTER_FACE_MASK_CATALOG)
      ? window.MASTER_FACE_MASK_CATALOG : [];
    return catalog.find((entry) => String(entry?.particle_profile || "") === profile.id) || null;
  }

  function apply(index, reason) {
    const world = window.MASTER_FACE_WORLD;
    if (!world?.setSubjectForm) return false;
    const profile = PROFILES[((index % PROFILES.length) + PROFILES.length) % PROFILES.length];
    const source = sourceFor(profile);
    const characters = window.MASTER_FACE_MASK_CHARACTERS && typeof window.MASTER_FACE_MASK_CHARACTERS === "object"
      ? window.MASTER_FACE_MASK_CHARACTERS : {};
    const characterId = window.MASTER_FACE_CHARACTER_ID || null;
    const character = characterId && characters[String(characterId)] &&
      typeof characters[String(characterId)] === "object"
      ? characters[String(characterId)] : null;
    world.setSubjectForm("object", descriptor(profile));

    const root = document.documentElement;
    root.dataset.maskProfile = profile.id;
    root.dataset.maskFamily = profile.family;
    root.dataset.maskLabel = profile.name;
    if (character?.id) root.dataset.maskCharacter = String(character.id);
    else delete root.dataset.maskCharacter;
    if (source) {
      root.dataset.maskSourceTitle = String(source.title || "");
      root.dataset.maskSourceCollection = String(source.collection || "");
      root.dataset.maskSourceRights = String(source.rights || "");
    } else {
      delete root.dataset.maskSourceTitle;
      delete root.dataset.maskSourceCollection;
      delete root.dataset.maskSourceRights;
    }

    const canvas = document.getElementById?.("face");
    if (canvas) {
      canvas.removeAttribute?.("title");
      canvas.setAttribute?.("aria-label", "MASTER monochrome particle mask");
    }

    window.dispatchEvent(new CustomEvent("master:mask-profile", {
      detail: {
        id: profile.id, name: profile.name, family: profile.family,
        note: profile.note, index, reason,
        character: character ? {
          id: String(character.id || ""),
          name: String(character.name || ""),
          signature: String(character.signature || "")
        } : null,
        source: source ? {
          id: source.id, title: source.title, collection: source.collection,
          accession: source.accession, object_url: source.object_url,
          rights: source.rights, image_credit: source.image_credit || source.collection
        } : null
      }
    }));
    try { sessionStorage.setItem("master.mask." + activeKey, String(index)); } catch (_) {}
    return true;
  }

  let activeKey = conversationKey();
  const serverProfileId = String(window.MASTER_FACE_MASK_PROFILE || "");
  const serverProfileIndex = ROTATION_PROFILE_IDS.indexOf(serverProfileId);
  let rotationIndex = serverProfileIndex >= 0
    ? serverProfileIndex
    : hash(activeKey) % ROTATION_PROFILE_IDS.length;
  let current = profileIndex(ROTATION_PROFILE_IDS[rotationIndex]);

  // A fresh chat page receives the signed server-side round-robin selection.
  // Storage is only a fallback for standalone/offline face previews.
  if (serverProfileIndex < 0 && activeKey) {
    try {
      const raw = sessionStorage.getItem("master.mask." + activeKey);
      const stored = raw === null ? NaN : Number(raw);
      const storedProfile = Number.isInteger(stored) ? PROFILES[stored] : null;
      const storedRotation = storedProfile
        ? ROTATION_PROFILE_IDS.indexOf(storedProfile.id) : -1;
      if (storedRotation >= 0) {
        rotationIndex = storedRotation;
        current = stored;
      }
    } catch (_) { /* private browsing: use the deterministic session fallback */ }
  }

  function rotate(event) {
    const nextKey = String(event?.detail?.conversationId || event?.detail?.id || "");
    if (!nextKey || nextKey === activeKey) return false;
    activeKey = nextKey;
    const serverIndex = ROTATION_PROFILE_IDS.indexOf(String(event?.detail?.faceProfile || ""));
    rotationIndex = serverIndex >= 0 ? serverIndex : (rotationIndex + 1) % ROTATION_PROFILE_IDS.length;
    current = profileIndex(ROTATION_PROFILE_IDS[rotationIndex]);
    try { sessionStorage.setItem("master.mask." + nextKey, String(current)); } catch (_) {}
    return apply(current, "new-conversation");
  }

  function start() {
    apply(current, "conversation-start");
  }
  window.MASTER_FACE_MASKS = Object.freeze({
    profiles: PROFILES,
    rotationProfiles: ROTATION_PROFILE_IDS,
    current: () => PROFILES[current],
    source: () => sourceFor(PROFILES[current]),
    descriptor: () => descriptor(PROFILES[current]),
    sample,
    normalAt,
    fieldAt: (id, ...point) => fields.get(id)?.(...point) ?? null,
    mouthGeometry,
    hasProfile: (id) => profileIndex(id) >= 0,
    applyCurrent: (reason = "restore") => apply(current, reason),
    select: (id) => {
      const index = profileIndex(id);
      if (index < 0) return false;
      current = index;
      const selectedRotation = ROTATION_PROFILE_IDS.indexOf(String(id));
      rotationIndex = selectedRotation >= 0 ? selectedRotation : ROTATION_PROFILE_IDS.length - 1;
      return apply(current, "explicit-selection");
    },
    next: () => {
      rotationIndex = (rotationIndex + 1) % ROTATION_PROFILE_IDS.length;
      current = profileIndex(ROTATION_PROFILE_IDS[rotationIndex]);
      return apply(current, "manual-cycle");
    },
    newConversation: (id, faceProfile) => {
      const conversationId = String(id || "").trim();
      if (!conversationId) return false;
      return rotate({ detail: { conversationId, faceProfile } });
    }
  });

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
  window.addEventListener("master:face-ready", start, { once: true });
  window.addEventListener("master:conversation-created", rotate);
  window.addEventListener("master:bus", (event) => {
    const detail = event.detail || {};
    if (detail.type === "conversation:created" || detail.type === "chat:created") {
      rotate({ detail: detail.payload || detail });
    }
  });
})();
