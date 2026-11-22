// The selfies gallery: a Swiper rail of a subject's stills and films, over the
// dilla bed. The manifest is generated (lora/selfies-manifest.js) and lists what
// exists; nothing here reads the network on its own. No innerHTML, no eval —
// every node is built with createElement and textContent, the same rule rg69.js
// follows. If Swiper or the manifest is missing, the page says so plainly
// rather than failing silently.
(() => {
  const root = document.querySelector("[data-selfies]");
  const status = document.querySelector("[data-selfies-status]");
  const empty = document.querySelector("[data-selfies-empty]");
  const soundtrack = document.querySelector("[data-selfies-soundtrack]");
  if (!root || !status) return;

  const manifest = window.STUDIO_SELFIES;
  const items = Array.isArray(manifest?.items) ? manifest.items : [];

  if (items.length === 0) {
    status.textContent = manifest
      ? "The manifest lists no renders yet."
      : "No manifest found — build it from the renders in lora/.";
    status.dataset.state = "empty";
    empty?.removeAttribute("hidden");
    return;
  }

  if (typeof window.Swiper !== "function") {
    status.textContent = "Swiper failed to load; showing the series as a plain list.";
    status.dataset.state = "error";
    renderPlainList(root.querySelector("[data-selfies-wrapper]"), items);
    root.removeAttribute("hidden");
    wireSoundtrack(soundtrack, manifest);
    return;
  }

  const wrapper = root.querySelector("[data-selfies-wrapper]");
  items.forEach((item, index) => wrapper.append(slide(item, index + 1, items.length)));

  const total = root.querySelector("[data-selfies-total]");
  const position = root.querySelector("[data-selfies-position]");
  if (total) total.textContent = String(items.length);

  new window.Swiper(root.querySelector("[data-selfies-swiper]"), {
    slidesPerView: 1,
    spaceBetween: 16,
    keyboard: { enabled: true },
    a11y: { enabled: true },
    navigation: {
      prevEl: root.querySelector("[data-selfies-prev]"),
      nextEl: root.querySelector("[data-selfies-next]"),
    },
    pagination: {
      el: root.querySelector("[data-selfies-pagination]"),
      clickable: true,
    },
    on: {
      slideChange(swiper) {
        if (position) position.textContent = String(swiper.realIndex + 1);
      },
    },
  });

  status.hidden = true;
  root.removeAttribute("hidden");
  wireSoundtrack(soundtrack, manifest);
})();

// One slide: a film plays inline (muted, looped, poster-first); a still is an
// image. The caption names the subject and the sitting, which is the only
// readable description a generated frame has.
function slide(item, number, count) {
  const figure = document.createElement("figure");
  figure.className = "swiper-slide";
  figure.setAttribute("role", "group");
  figure.setAttribute("aria-roledescription", "slide");
  figure.setAttribute("aria-label", `${number} of ${count}`);

  const label = item.caption || `${item.subject || "subject"} selfie ${number}`;

  if (item.kind === "film" && item.src) {
    const video = document.createElement("video");
    video.src = item.src;
    if (item.poster) video.poster = item.poster;
    video.controls = true;
    video.loop = true;
    video.muted = true;
    video.playsInline = true;
    video.preload = "metadata";
    video.setAttribute("aria-label", label);
    figure.append(video);
  } else if (item.src) {
    const image = document.createElement("img");
    image.src = item.src;
    image.alt = label;
    image.loading = "lazy";
    image.decoding = "async";
    figure.append(image);
  }

  const caption = document.createElement("figcaption");
  caption.className = "visually-hidden";
  caption.textContent = label;
  figure.append(caption);
  return figure;
}

// The no-Swiper fallback: the same figures in a plain scroll list, so the
// series is still readable when the carousel library does not arrive.
function renderPlainList(wrapper, items) {
  const list = document.createElement("ol");
  list.className = "selfies-plain";
  items.forEach((item, index) => {
    const entry = document.createElement("li");
    entry.append(slide(item, index + 1, items.length));
    list.append(entry);
  });
  wrapper.replaceWith(list);
}

// The soundtrack is the rendered dilla bed the films are cut to. It never
// autoplays: the reader starts it, and the button reports the state.
function wireSoundtrack(section, manifest) {
  const src = manifest?.soundtrack;
  const audio = section?.querySelector("[data-selfies-audio]");
  const toggle = section?.querySelector("[data-selfies-audio-toggle]");
  if (!section || !audio || !toggle || !src) return;

  audio.src = src;
  section.removeAttribute("hidden");
  toggle.addEventListener("click", async () => {
    if (audio.paused) {
      try {
        await audio.play();
        toggle.setAttribute("aria-pressed", "true");
        toggle.textContent = "Pause the dilla bed";
      } catch {
        toggle.textContent = "The bed would not play";
      }
    } else {
      audio.pause();
      toggle.setAttribute("aria-pressed", "false");
      toggle.textContent = "Play the dilla bed";
    }
  });
}
