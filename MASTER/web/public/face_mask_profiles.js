/* MASTER pixel-mask profile catalogue.
 * A bounded relief sampler morphs the existing face point field; no second renderer,
 * bitmap, connected mesh, or downloaded asset is introduced. Cultural labels
 * identify reference families, not claims of ceremonial authenticity.
 */
(() => {
  "use strict";

  const PROFILES = Object.freeze([
    { id: "iatmul-river", name: "MASTER — River", family: "Original Sepik study", note: "Original carved particle volume; not a museum scan", outer: "ring", w: 0.405, h: 0.56, jaw: 0.24, crown: 0.29, asym: 0.018, brow: 0.34, nose: 0.32, mouth: 0.2 },
    { id: "iatmul-concentric", name: "MASTER — Orbit", family: "Original Iatmul study", note: "Original carved particle volume; not a museum scan", outer: "ring", w: 0.445, h: 0.5, jaw: 0.26, crown: 0.31, asym: 0.024, brow: 0.37, nose: 0.28, mouth: 0.21 },
    { id: "sepik-split", name: "MASTER — Rift", family: "Original Sepik study", note: "Original carved particle volume; not a museum scan", outer: "ring", w: 0.335, h: 0.61, jaw: 0.18, crown: 0.27, asym: 0.044, brow: 0.3, nose: 0.36, mouth: 0.18 },
    { id: "tatanua-crest", name: "MASTER — Crest", family: "Original New Ireland study", note: "Original carved particle volume; not a museum scan", outer: "ring", w: 0.4, h: 0.59, jaw: 0.21, crown: 0.34, asym: 0.03, brow: 0.36, nose: 0.29, mouth: 0.19 },
    { id: "elema-hollow", name: "MASTER — Hollow", family: "Original Gulf study", note: "Original carved particle volume; not a museum scan", outer: "ring", w: 0.385, h: 0.54, jaw: 0.28, crown: 0.28, asym: 0.036, brow: 0.33, nose: 0.26, mouth: 0.22 }
  ]);

  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, Number(v) || 0));
  const beam = (key, center, size, axis = "x") => ({ key, primitive: "beam", center, size, axis });
  function descriptor(profile) {
    const w = clamp(profile.w, .22, .48);
    const h = clamp(profile.h, .30, .62);
    const jaw = clamp(profile.jaw, .10, .36);
    const asym = clamp(profile.asym, 0, .15);
    const mouth = clamp(profile.mouth ?? Math.min(.36, Math.max(.18, profile.crown * .62)), .14, .36);
    const eyeY = .15 - RELIEF[profile.id][2] * .25;
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
    "iatmul-river": [0.25, 2.15, 0.4, 0.185, 0.124, 0.09, 0.13, 0.055],
    "iatmul-concentric": [0.14, 2.55, 0.34, 0.195, 0.132, 0.093, 0.1, 0.065],
    "sepik-split": [0.35, 1.85, 0.43, 0.145, 0.106, 0.091, 0.16, 0.045],
    "tatanua-crest": [0.3, 2.75, 0.56, 0.18, 0.126, 0.088, 0.11, 0.05],
    "elema-hollow": [0.1, 1.95, 0.28, 0.17, 0.13, 0.105, 0.09, 0.045]
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

  // An implicit volume defines both the sampling field and relief normals.
  // Eye and mouth apertures subtract matter through the entire thickness.
  function section(p, shape, y) {
    const [taper, exponent, forehead] = shape;
    const v = Math.max(-.999, Math.min(.999, y / p.h));
    const outline = Math.pow(Math.max(.0001, 1 - Math.pow(Math.abs(v), exponent)), 1 / exponent);
    const erosion = 1 + .024 * Math.sin(v * 37) + .013 * Math.cos(v * 71);
    return { width: p.w * (1 + forehead * .24 * Math.max(0, v)) * outline *
      (1 - taper * Math.max(0, -v)) * erosion, center: p.asym * v * .45, outline };
  }

  function volumeAt(p, shape, mouth, x, y) {
    const [, , forehead, eyeX, eyeW, eyeH, noseDepth, cheeks] = shape;
    const slice = section(p, shape, y);
    const edge = Math.abs((x - slice.center) / slice.width);
    const eyeY = .15 - forehead * .25;
    const ax = Math.abs(x);
    const eye = ((ax - eyeX) / eyeW) ** 2 + ((y - eyeY) / eyeH) ** 2;
    const smile = .018 * Math.min(1, (x / mouth.width) ** 2);
    const lip = (x / mouth.width) ** 2 + ((y - mouth.y - smile) / mouth.height) ** 2;
    const curvature = Math.sqrt(Math.max(0, 1 - edge * edge));
    const brow = gaussian(y - eyeY - eyeH * 1.35, .045) * gaussian(ax - eyeX, .15);
    const bridge = gaussian(x, .045 + noseDepth * .12) * gaussian(y + .025, p.nose * .64);
    const cheek = gaussian(ax - p.w * .60, .11) * gaussian(y + .12, .19);
    const rim = gaussian(eye - 1.22, .65) + gaussian(lip - 1.24, .78);
    const front = .025 + .21 * curvature + noseDepth * bridge + .026 * brow + cheeks * cheek +
      .014 * Math.min(1, rim);
    const rear = -.43 * curvature * slice.outline;
    const grain = .5 + .5 * Math.sin(x * 67 + Math.cos(y * 33) * 2) * Math.cos(y * 53 - x * 11);
    const density = Math.min(1, .27 + .20 * edge + .18 * bridge + .13 * rim + .16 * grain);
    return { front, rear, density, inside: edge <= 1 && eye >= 1 && lip >= 1 };
  }

  function normalAt(id, x, y, z = 0) {
    const p = PROFILES[profileIndex(id)], shape = RELIEF[id];
    if (!p || !shape) return [0, 0, 1];
    const mouth = mouthGeometry(id), surface = z < 0 ? "rear" : "front";
    const h = .006;
    const height = (a, b) => volumeAt(p, shape, mouth, a, b)[surface];
    const dx = (height(x + h, y) - height(x - h, y)) / (2 * h);
    const dy = (height(x, y + h) - height(x, y - h)) / (2 * h);
    const sign = z < 0 ? -1 : 1;
    const length = Math.hypot(dx, dy, 1);
    return [-sign * dx / length, -sign * dy / length, sign / length];
  }

  function sample(id, index) {
    const p = PROFILES[profileIndex(id)], shape = RELIEF[id];
    if (!p || !shape) return null;
    const mouth = mouthGeometry(id);
    const contract = window.MASTER_FACE_CONTRACT?.sculpture || {};
    const coreFraction = clamp(contract.interior_fraction ?? .40, .20, .65);
    const rearFraction = clamp(contract.rear_fraction ?? .24, .15, .30);
    const cohort = randomUnit(index, 195);
    const frac = (n) => n - Math.floor(n);
    for (let attempt = 0; attempt < 64; attempt += 1) {
      const salt = attempt * 5;
      const v = frac((index + .5) * .7548776662466927 + attempt * .5698402909980532 +
        .026 * randomUnit(index, salt)) * 2 - 1;
      const u = frac((index + .5) * .5698402909980532 + attempt * .7548776662466927 +
        .026 * randomUnit(index, salt + 1)) * 2 - 1;
      const y = v * p.h;
      const slice = section(p, shape, y);
      const x = slice.center + u * slice.width;
      const field = volumeAt(p, shape, mouth, x, y);
      if (!field.inside || randomUnit(index, salt + 2) > field.density) continue;
      const t = cohort < rearFraction ? .025 + .045 * randomUnit(index, salt + 3)
        : cohort < rearFraction + coreFraction ? .15 + .70 * randomUnit(index, salt + 3)
        : .94 + .06 * randomUnit(index, salt + 3);
      return [x, y, field.rear + (field.front - field.rear) * t];
    }
    const y = p.h * (.86 + .08 * randomUnit(index, 193));
    const slice = section(p, shape, y);
    return [slice.center + slice.width * (randomUnit(index, 194) - .5), y, .025];
  }

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
    const search = window.location?.search || "";
    // The opt-in material laboratory uses the unmasked portrait; production
    // always starts with the selected volume.
    if (!/(?:^|[?&])stipple=0(?:&|$)/.test(search) &&
        /(?:^|[?&])(?:stipple|playground)=1(?:&|$)/.test(search)) {
      window.MASTER_FACE_WORLD?.setSubjectForm?.("face");
      return;
    }
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
