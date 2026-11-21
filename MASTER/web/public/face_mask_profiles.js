/* MASTER pixel-mask profile catalogue.
 * Six sparse primitives morph the existing face point field; no second renderer,
 * bitmap, connected mesh, or downloaded asset is introduced. Cultural labels
 * identify reference families, not claims of ceremonial authenticity.
 */
(() => {
  "use strict";

  const PROFILES = Object.freeze([
    { id: "abelam-shield", name: "Abelam Shield", family: "Abelam / East Sepik", note: "Stepped shield silhouette and nested planes", w: .40, h: .54, jaw: .25, crown: .42, asym: .00, brow: .34, nose: .40 },
    { id: "abelam-prow", name: "Abelam Prow", family: "Abelam / East Sepik", note: "Tall prow with a tapered lower face", w: .29, h: .62, jaw: .12, crown: .28, asym: .02, brow: .27, nose: .52 },
    { id: "iatmul-river", name: "Iatmul River Face", family: "Iatmul / Sepik", note: "Elongated vertical proportions and projecting bridge", w: .31, h: .60, jaw: .18, crown: .26, asym: .00, brow: .26, nose: .58 },
    { id: "iatmul-concentric", name: "Iatmul Concentric", family: "Iatmul / Sepik", note: "Broad brow and concentric orbital voids", w: .43, h: .47, jaw: .28, crown: .38, asym: .00, brow: .42, nose: .35 },
    { id: "sepik-split", name: "Sepik Split Face", family: "Sepik formal study", note: "Asymmetric broad and narrow halves", w: .44, h: .50, jaw: .24, crown: .40, asym: .13, brow: .38, nose: .42 },
    { id: "elema-tower", name: "Elema Spirit Tower", family: "Elema / Gulf", note: "High forehead and low-set features", w: .33, h: .64, jaw: .17, crown: .25, asym: .01, brow: .30, nose: .47 },
    { id: "elema-hollow", name: "Elema Hollow Arch", family: "Elema / Gulf", note: "Open vaulted eye region and strong central ridge", w: .39, h: .53, jaw: .20, crown: .35, asym: .00, brow: .43, nose: .50 },
    { id: "tatanua-crest", name: "Tatanua Crest", family: "New Ireland", note: "Raised asymmetric crest and compact lower face", w: .39, h: .53, jaw: .20, crown: .50, asym: .15, brow: .36, nose: .39 },
    { id: "malangan-double", name: "Malangan Double Visage", family: "New Ireland", note: "Nested inner and outer face contours", w: .44, h: .54, jaw: .27, crown: .39, asym: .02, brow: .38, nose: .39 },
    { id: "woven-void", name: "Woven Void", family: "Original synthesis", note: "Open lattice rhythm; voids carry the expression", w: .41, h: .51, jaw: .24, crown: .38, asym: .00, brow: .33, nose: .34 },
    { id: "mak-yong-court", name: "Mak Yong Court", family: "Malay theatre / Kelantan", note: "Composed brows, narrow eyes and restrained mouth", w: .37, h: .48, jaw: .22, crown: .34, asym: .00, brow: .40, nose: .31 },
    { id: "mak-yong-character", name: "Mak Yong Character", family: "Malay theatre / Kelantan", note: "Sharper brow and expressive cheek planes", w: .40, h: .50, jaw: .23, crown: .35, asym: .04, brow: .45, nose: .36 },
    { id: "mek-mulung-hero", name: "Mek Mulung Hero", family: "Malay theatre / Kedah", note: "Strong brow and broad cheek structure", w: .44, h: .49, jaw: .28, crown: .37, asym: .02, brow: .46, nose: .35 },
    { id: "jikey-comic", name: "Jikey Comic", family: "Malay theatre / Kedah–Perlis", note: "Playful compressed proportions and broad expression", w: .48, h: .42, jaw: .34, crown: .36, asym: .06, brow: .48, nose: .27 },
    { id: "mah-meri-organic", name: "Mah Meri Carved Form", family: "Orang Asli / Mah Meri", note: "Organic silhouette with softened planes", w: .40, h: .50, jaw: .26, crown: .36, asym: .03, brow: .35, nose: .34 },
    { id: "jah-hut-angular", name: "Jah Hut Angular Form", family: "Orang Asli / Jah Hut", note: "Faceted profile with angular cheek transitions", w: .38, h: .52, jaw: .18, crown: .37, asym: .02, brow: .42, nose: .43 }
  ]);

  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, Number(v) || 0));
  const beam = (key, center, size, axis = "x") => ({ key, primitive: "beam", center, size, axis });
  function descriptor(profile) {
    const w = clamp(profile.w, .22, .48);
    const h = clamp(profile.h, .30, .64);
    const jaw = clamp(profile.jaw, .10, .36);
    const asym = clamp(profile.asym, 0, .15);
    const eyeY = profile.id === "elema-tower" ? .02 : .12;
    const parts = [
      { key: "outer", primitive: "ring", center: [asym * .25, 0, .04], size: [w, h, .08] },
      beam("crown", [asym * .4, .39, .05], [profile.crown, .035, .035]),
      beam("brow", [asym, .25, .08], [profile.brow, .035, .035]),
      { key: "left-eye", primitive: "ring", center: [-.18 - asym, eyeY, .13], size: [.105, .060, .04] },
      { key: "right-eye", primitive: "ring", center: [.18 + asym, eyeY, .13], size: [.105, .060, .04] },
      beam("nose", [asym * .4, -.06, .16], [.045, profile.nose, .045], "y"),
      beam("cheeks", [asym, -.13, .045], [Math.max(.18, jaw * 1.55), .028, .035]),
      beam("jaw", [asym, -.31, .06], [Math.max(.16, jaw * 1.65), .035, .04])
    ];
    return {
      kind: "custom",
      label: profile.name,
      confidence: 1,
      sequence: ["outer", "crown", "brow", "left-eye", "right-eye", "nose", "cheeks", "jaw"],
      parts
    };
  }

  function hash(value) {
    let h = 2166136261;
    for (const char of String(value)) h = Math.imul(h ^ char.charCodeAt(0), 16777619);
    return h >>> 0;
  }
  function conversationKey() {
    const explicit = window.MASTER_CONVERSATION_ID ||
      document.querySelector('meta[name="master-conversation-id"]')?.content ||
      document.querySelector("[data-conversation-id]")?.getAttribute("data-conversation-id") ||
      window.history?.state?.conversationId;
    return explicit == null ? "" : String(explicit);
  }
  function apply(index, reason) {
    const world = window.MASTER_FACE_WORLD;
    if (!world?.setConversationSubject) return false;
    const profile = PROFILES[((index % PROFILES.length) + PROFILES.length) % PROFILES.length];
    world.setConversationSubject("pixel mask", descriptor(profile));
    document.documentElement.dataset.maskProfile = profile.id;
    document.documentElement.dataset.maskFamily = profile.family;
    document.documentElement.dataset.maskLabel = profile.name;
    window.dispatchEvent(new CustomEvent("master:mask-profile", {
      detail: { id: profile.id, name: profile.name, family: profile.family, note: profile.note, index, reason }
    }));
    return true;
  }

  const key = conversationKey();
  const initial = key ? hash(key) % PROFILES.length : 0;
  let current = initial;
  if (key) {
    try {
      const stored = sessionStorage.getItem("master.mask." + key);
      if (stored !== null && Number.isInteger(Number(stored))) current = Number(stored) % PROFILES.length;
      else sessionStorage.setItem("master.mask." + key, String(current));
    } catch (_) { /* private browsing: deterministic URL fallback remains */ }
  }

  function rotate(event) {
    const nextKey = String(event?.detail?.conversationId || event?.detail?.id || "");
    if (!nextKey || nextKey === key) return;
    current = (hash(nextKey) % PROFILES.length);
    try { sessionStorage.setItem("master.mask." + nextKey, String(current)); } catch (_) {}
    apply(current, "new-conversation");
  }

  function start() {
    apply(current, "conversation-start");
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
  window.addEventListener("master:conversation-created", rotate);
  window.addEventListener("master:bus", (event) => {
    const detail = event.detail || {};
    if (detail.type === "conversation:created" || detail.type === "chat:created") {
      rotate({ detail: detail.payload || detail });
    }
  });
  window.MASTER_FACE_MASKS = Object.freeze({
    profiles: PROFILES,
    current: () => PROFILES[current],
    select: (id) => {
      const index = PROFILES.findIndex((profile) => profile.id === String(id));
      if (index < 0) return false;
      current = index;
      return apply(current, "explicit-selection");
    },
    next: () => { current = (current + 1) % PROFILES.length; return apply(current, "manual-cycle"); }
  });
})();
