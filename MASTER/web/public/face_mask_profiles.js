/* MASTER pixel-mask profile catalogue.
 * Eight bounded parts morph the existing face point field; no second renderer,
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
      label: profile.name,
      confidence: 1,
      sequence: ["outer", "brow", "left-eye", "right-eye", "nose", cheekKey, "mouth", "jaw"],
      parts
    };
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
    if (canvas && source) {
      const credit = String(source.image_credit || source.collection || "");
      const characterPrefix = characterName ? `${characterName}. ` : "";
      canvas.title = `${characterPrefix}${profile.name} — original particle study. Reference: ${source.title || "collection object"}; ${source.collection || "collection"}; ${credit}.`;
      canvas.setAttribute?.(
        "aria-label",
        `${characterPrefix}${profile.name}, an original monochrome particle-face study. Reference object: ${source.title || "collection object"}, ${source.collection || "collection"}. ${credit}.`
      );
    } else if (canvas) {
      canvas.removeAttribute?.("title");
      canvas.setAttribute?.("aria-label", "MASTER original monochrome particle face");
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
      const stored = Number(sessionStorage.getItem("master.mask." + activeKey));
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
    rotationIndex = (rotationIndex + 1) % ROTATION_PROFILE_IDS.length;
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
      rotate({ detail: { conversationId } });
      return true;
    }
  });
})();
