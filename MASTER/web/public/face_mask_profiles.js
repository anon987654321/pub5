/* MASTER pixel-mask profile catalogue.
 * A bounded relief sampler morphs the existing face point field; no second renderer,
 * bitmap, connected mesh, or downloaded asset is introduced. Cultural labels
 * identify reference families, not claims of ceremonial authenticity.
 */
(() => {
  "use strict";

  const PROFILES = Object.freeze([
    { id: "abelam-shield", name: "Abelam Shield", family: "Abelam / East Sepik", note: "Stepped shield silhouette and nested planes", outer: "box", w: .40, h: .54, jaw: .25, crown: .42, asym: .00, brow: .34, nose: .40 },
    { id: "abelam-prow", name: "Abelam Prow", family: "Abelam / East Sepik", note: "Tall prow with a tapered lower face", outer: "box", crownAxis: "y", w: .29, h: .62, jaw: .12, crown: .28, asym: .02, brow: .27, nose: .52 },
    { id: "iatmul-river", name: "Iatmul Mai — Long Face", family: "Iatmul / Middle Sepik", note: "Elongated human-face proportions; original particle study only", outer: "ring", w: .32, h: .62, jaw: .18, crown: .22, asym: .00, brow: .33, nose: .48, mouth: .19 },
    { id: "iatmul-concentric", name: "Iatmul Human Face", family: "Iatmul / East Sepik", note: "Broad oval, readable human-face proportions; original particle study only", outer: "ring", w: .42, h: .58, jaw: .25, crown: .38, asym: .00, brow: .40, nose: .38, mouth: .26 },
    { id: "sepik-split", name: "Iatmul Mwai", family: "Iatmul / Middle Sepik", note: "Long oval human face with a strong bridge; original particle study only", outer: "ring", w: .36, h: .61, jaw: .20, crown: .34, asym: .02, brow: .36, nose: .50, mouth: .20 },
    { id: "elema-tower", name: "Elema Spirit Tower", family: "Elema / Gulf", note: "High forehead and low-set features", outer: "cylinder", crownAxis: "y", w: .33, h: .64, jaw: .17, crown: .25, asym: .01, brow: .30, nose: .47 },
    { id: "elema-hollow", name: "Elema Eharo Human Face", family: "Elema / Gulf Province", note: "Broad human-face planes; original particle study only", outer: "ring", w: .43, h: .55, jaw: .28, crown: .34, asym: .00, brow: .42, nose: .42, mouth: .28 },
    { id: "tatanua-crest", name: "Tatanua Human Face", family: "New Ireland", note: "Balanced oval human-face proportions; no crest or ornament is copied", outer: "ring", w: .40, h: .55, jaw: .24, crown: .40, asym: .01, brow: .38, nose: .39, mouth: .25 },
    { id: "malangan-double", name: "Malangan Double Visage", family: "New Ireland", note: "Nested inner and outer face contours", outer: "ring", inner: true, w: .44, h: .54, jaw: .27, crown: .39, asym: .02, brow: .38, nose: .39 },
    { id: "woven-void", name: "Woven Void", family: "Original synthesis", note: "Open lattice rhythm; voids carry the expression", outer: "ring", lattice: true, w: .41, h: .51, jaw: .24, crown: .38, asym: .00, brow: .33, nose: .34 },
    { id: "mak-yong-court", name: "Mak Yong Court", family: "Malay theatre / Kelantan", note: "Composed brows, narrow eyes and restrained mouth", outer: "sphere", w: .37, h: .48, jaw: .22, crown: .34, asym: .00, brow: .40, nose: .31 },
    { id: "mak-yong-character", name: "Mak Yong Character", family: "Malay theatre / Kelantan", note: "Sharper brow and expressive cheek planes", outer: "box", w: .40, h: .50, jaw: .23, crown: .35, asym: .04, brow: .45, nose: .36 },
    { id: "mek-mulung-hero", name: "Mek Mulung Hero", family: "Malay theatre / Kedah", note: "Strong brow and broad cheek structure", outer: "sphere", w: .44, h: .49, jaw: .28, crown: .37, asym: .02, brow: .46, nose: .35 },
    { id: "jikey-comic", name: "Jikey Comic", family: "Malay theatre / Kedah–Perlis", note: "Playful compressed proportions and broad expression", outer: "sphere", w: .48, h: .42, jaw: .34, crown: .36, asym: .06, brow: .48, nose: .27 },
    { id: "mah-meri-organic", name: "Mah Meri Carved Form", family: "Orang Asli / Mah Meri", note: "Organic silhouette with softened planes", outer: "sphere", w: .40, h: .50, jaw: .26, crown: .36, asym: .03, brow: .35, nose: .34 },
    { id: "jah-hut-angular", name: "Jah Hut Angular Form", family: "Orang Asli / Jah Hut", note: "Faceted profile with angular cheek transitions", outer: "box", w: .38, h: .52, jaw: .18, crown: .37, asym: .02, brow: .42, nose: .43 }
  ]);

  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, Number(v) || 0));
  const beam = (key, center, size, axis = "x") => ({ key, primitive: "beam", center, size, axis });
  function descriptor(profile) {
    const w = clamp(profile.w, .22, .48);
    const h = clamp(profile.h, .30, .62);
    const jaw = clamp(profile.jaw, .10, .36);
    const asym = clamp(profile.asym, 0, .15);
    const mouth = clamp(profile.mouth ?? Math.min(.36, Math.max(.18, profile.crown * .62)), .14, .36);
    const eyeY = profile.id === "elema-tower" ? -.02 : .12;
    const cheekPart = profile.inner
      ? { key: "inner-face", primitive: "ring", center: [asym * .2, -.02, .12], size: [w * .62, h * .66, .06] }
      : profile.lattice
        ? beam("lattice", [asym, -.13, .06], [.06, .20, .06], "y")
        : beam("cheeks", [asym, -.13, .06], [Math.max(.18, jaw * 1.55), .06, .06]);
    // The eight pieces use the original shared particle field. The outline,
    // eye wells, bridge, cheeks, mouth and jaw keep the result readable as a
    // human face without copying a source mask's surface or ceremonial motifs.
    const parts = [
      { key: "outer", primitive: profile.outer || "ring", center: [asym * .25, 0, .06], size: [w, h, .08] },
      beam("brow", [asym, .25, .08], [profile.brow, .06, .06]),
      { key: "left-eye", primitive: "ring", center: [-.18 - asym, eyeY, .13], size: [.105, .060, .06] },
      { key: "right-eye", primitive: "ring", center: [.18 + asym, eyeY, .13], size: [.105, .060, .06] },
      beam("nose", [asym * .4, -.06, .16], [.06, profile.nose, .06], "y"),
      cheekPart,
      beam("mouth", [asym, -.225, .14], [mouth, .06, .06]),
      beam("jaw", [asym, -.31, .06], [Math.max(.16, jaw * 1.65), .06, .06])
    ];
    const cheekKey = profile.inner ? "inner-face" : profile.lattice ? "lattice" : "cheeks";
    return {
      kind: "custom",
      maskProfile: profile.id,
      label: profile.name,
      confidence: 1,
      sequence: ["outer", "brow", "left-eye", "right-eye", "nose", cheekKey, "mouth", "jaw"],
      parts
    };
  }


  // Original geometric reliefs, not photographs or traced ceremonial designs.
  // Profiles vary independently in silhouette, eye voids, cheek fullness,
  // bridge depth and mouth proportions. All coordinates remain bounded.
  const RELIEF = Object.freeze({
    "abelam-shield":    [.14, 2.8, .25, .14, .12, .075, .20, .12],
    "abelam-prow":      [.42, 2.2, .34, .19, .10, .050, .28, .06],
    "iatmul-river":     [.47, 1.7, .43, .17, .10, .055, .32, .08],
    "iatmul-concentric":[.06, 2.0, .18, .22, .15, .095, .17, .22],
    "sepik-split":      [.30, 2.6, .38, .19, .13, .048, .30, .13],
    "elema-tower":      [.32, 3.2, .49, .17, .13, .055, .24, .05],
    "elema-hollow":     [-.12,2.5, .10, .23, .19, .105, .14, .30],
    "tatanua-crest":    [.22, 2.1, .28, .19, .12, .075, .20, .16],
    "malangan-double":  [.10, 2.4, .24, .21, .13, .075, .18, .26],
    "woven-void":       [.20, 1.8, .20, .21, .16, .090, .16, .10],
    "mak-yong-court":   [.27, 2.0, .26, .18, .11, .040, .12, .12],
    "mak-yong-character":[.21,2.8,.20, .20, .13, .065, .20, .16],
    "mek-mulung-hero":  [.00, 2.4, .22, .23, .13, .060, .19, .24],
    "jikey-comic":      [-.16,2.2, .12, .23, .16, .100, .10, .25],
    "mah-meri-organic": [.13, 1.6, .25, .20, .14, .080, .17, .20],
    "jah-hut-angular":  [.35, 3.0, .31, .18, .12, .045, .24, .12]
  });
  const randomUnit = (index, salt) => {
    let n = Math.imul((index + 1) ^ Math.imul(salt + 1, 0x9e3779b1), 0x85ebca6b);
    n = Math.imul(n ^ (n >>> 13), 0xc2b2ae35);
    return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
  };
  const gaussian = (v, width) => Math.exp(-Math.pow(v / width, 2));
  function mouthGeometry(id) {
    const p = PROFILES[profileIndex(id)];
    const shape = RELIEF[id];
    if (!p || !shape) return null;
    const forehead = shape[2], cheeks = shape[7];
    return { y: -.26 - forehead * .09, width: (p.mouth ?? p.crown * .62) * .56,
      height: .035 + cheeks * .11 };
  }

  // Local relief derivatives, not normals from the unrelated base portrait.
  function normalAt(id, x, y, z = 0) {
    const p = PROFILES[profileIndex(id)];
    const shape = RELIEF[id];
    if (!p || !shape) return [0, 0, 1];
    const [taper, exponent, forehead, eyeX, eyeW, eyeH, noseDepth, cheeks] = shape;
    const eyeY = .15 - forehead * .25;
    const mouth = mouthGeometry(id);
    const height = (a, b) => {
      const v = Math.max(-.999, Math.min(.999, b / p.h));
      const width = p.w * Math.pow(Math.max(.0001, 1 - Math.pow(Math.abs(v), exponent)), 1 / exponent) *
        (1 - taper * Math.max(0, -v));
      const edge = Math.min(1, Math.abs((a - p.asym * v * .45) / width));
      const absX = Math.abs(a);
      const eye = ((absX - eyeX) / eyeW) ** 2 + ((b - eyeY) / eyeH) ** 2;
      const lip = (a / mouth.width) ** 2 + ((b - mouth.y) / mouth.height) ** 2;
      const brow = gaussian(b - eyeY - eyeH * 1.35, .045) * gaussian(absX - eyeX, .15);
      const bridge = gaussian(a, .035 + noseDepth * .12) * gaussian(b + .025, p.nose * .64);
      const cheek = gaussian(absX - p.w * .60, .095) * gaussian(b + .12, .18);
      const rim = gaussian(eye - 1.22, .65) + gaussian(lip - 1.24, .78);
      return .035 + .11 * Math.sqrt(Math.max(0, 1 - edge * edge)) + noseDepth * bridge +
        .085 * brow + cheeks * cheek + .036 * Math.min(1, rim);
    };
    const h = .006;
    const dx = (height(x + h, y) - height(x - h, y)) / (2 * h);
    const dy = (height(x, y + h) - height(x, y - h)) / (2 * h);
    const length = Math.hypot(dx, dy, 1);
    if (z < 0) {
      const nx = x / (p.w * p.w), ny = y / (p.h * p.h), nz = z / (.24 * .24);
      const magnitude = Math.hypot(nx, ny, nz) || 1;
      return [nx / magnitude, ny / magnitude, nz / magnitude];
    }
    return [-dx / length, -dy / length, 1 / length];
  }

  function sample(id, index) {
    const p = PROFILES[profileIndex(id)];
    const shape = RELIEF[id];
    if (!p || !shape) return null;
    const [taper, exponent, forehead, eyeX, eyeW, eyeH, noseDepth, cheeks] = shape;
    const eyeY = .15 - forehead * .25;
    const { y: mouthY, width: mouthW, height: mouthH } = mouthGeometry(id);
    const w = p.w, h = p.h;
    // Bounded rejection sampling leaves real holes rather than drawing dark
    // sprites over a solid face. Same index and profile always yield same point.
    for (let attempt = 0; attempt < 48; attempt += 1) {
      const salt = attempt * 4;
      // Additive low-discrepancy sequence distributes first candidates
      // across the surface; later attempts preserve the same bounded density.
      const frac = (n) => n - Math.floor(n);
      const v = frac((index + .5) * .7548776662466927 + attempt * .5698402909980532) * 2 - 1;
      const u = frac((index + .5) * .5698402909980532 + attempt * .7548776662466927) * 2 - 1;
      const y = v * h;
      const width = Math.pow(Math.max(0, 1 - Math.pow(Math.abs(v), exponent)), 1 / exponent);
      const jaw = 1 - taper * Math.max(0, -v);
      const x = u * w * width * jaw + p.asym * v * .45;
      const absoluteX = Math.abs(x);
      const eye = Math.pow((absoluteX - eyeX) / eyeW, 2) + Math.pow((y - eyeY) / eyeH, 2);
      const mouth = Math.pow(x / mouthW, 2) + Math.pow((y - mouthY) / mouthH, 2);
      if (eye < 1 || mouth < 1) continue;
      const edge = Math.abs(u);
      const brow = gaussian(y - eyeY - eyeH * 1.35, .045) * gaussian(absoluteX - eyeX, .15);
      const bridge = gaussian(x, .035 + noseDepth * .12) * gaussian(y + .025, p.nose * .64);
      const cheek = gaussian(absoluteX - w * .60, .095) * gaussian(y + .12, .18);
      const rim = gaussian(eye - 1.22, .65) + gaussian(mouth - 1.24, .78);
      const relief = .035 + .11 * Math.sqrt(Math.max(0, 1 - edge * edge)) +
        noseDepth * bridge + .085 * brow + cheeks * cheek + .036 * Math.min(1, rim);
      const light = Math.min(1, .19 + .29 * edge + .35 * bridge + .22 * brow + .18 * rim + .30 * cheek);
      // A minority of stable carriers describes the curved rear shell.
      // Keep the same projected apertures through both sides of the mask.
      const rear = index % 4 === 0;
      if (!rear && randomUnit(index, salt + 2) > light) continue;
      const z = rear ? -.24 * Math.sqrt(Math.max(0, 1 - edge * edge)) * width
        : relief + (randomUnit(index, salt + 3) - .5) * .028;
      return [x, y, z];
    }
    // Bounded fallback on the silhouette, never in an eye or mouth void.
    const angle = randomUnit(index, 193) * Math.PI * 2;
    const v = Math.sin(angle);
    return [Math.cos(angle) * w * (1 - taper * Math.max(0, -v)), v * h, .025];
  }

  function hash(value) {
    let h = 2166136261;
    for (const char of String(value)) h = Math.imul(h ^ char.charCodeAt(0), 16777619);
    return h >>> 0;
  }
  const ROTATION_PROFILE_IDS = Object.freeze([
    "iatmul-concentric",
    "iatmul-river",
    "sepik-split",
    "tatanua-crest",
    "elema-hollow"
  ]);

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
    const characterRotation = Array.isArray(window.MASTER_FACE_MASK_CHARACTER_ROTATION)
      ? window.MASTER_FACE_MASK_CHARACTER_ROTATION : [];
    const characterId = characterRotation[ROTATION_PROFILE_IDS.indexOf(profile.id)];
    const character = characterId && characters[String(characterId)] &&
      typeof characters[String(characterId)] === "object"
      ? characters[String(characterId)] : null;
    const characterName = String(character?.name || "");
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
  window.MASTER_FACE_MASKS = Object.freeze({
    profiles: PROFILES,
    rotationProfiles: ROTATION_PROFILE_IDS,
    current: () => PROFILES[current],
    source: () => sourceFor(PROFILES[current]),
    descriptor: () => descriptor(PROFILES[current]),
    sample,
    normalAt,
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
    newConversation: (id) => {
      const conversationId = String(id || "").trim();
      if (!conversationId) return false;
      return rotate({ detail: { conversationId } });
    }
  });
})();
