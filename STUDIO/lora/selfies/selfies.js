"use strict";

// The selfie gallery. Reads window.STUDIO_SELFIES (written by
// STUDIO/lora/selfies_gallery.rb) and builds the rail with created nodes only —
// the page never assigns innerHTML and never evals a string. When the vendored
// Swiper 11 is present it drives the rail; otherwise the rail falls back to CSS
// scroll snapping. The dilla bed is opt-in and never autoplays.

(function () {
  var manifest = window.STUDIO_SELFIES;
  var status = document.getElementById("gallery-status");
  var track = document.getElementById("gallery-track");
  var rail = document.getElementById("gallery-rail");
  var empty = document.getElementById("gallery-empty");
  var filterBox = document.getElementById("subject-filter");
  var fitToggle = document.getElementById("fit-toggle");
  var bedToggle = document.getElementById("bed-toggle");
  var prev = document.getElementById("rail-prev");
  var next = document.getElementById("rail-next");
  var swiper = null;
  var bed = null;

  function say(message) {
    if (status) { status.textContent = message; }
  }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text) { node.textContent = text; }
    return node;
  }

  function currentSubjects() {
    var buttons = filterBox ? filterBox.querySelectorAll("button[data-subject]") : [];
    var active = [];
    buttons.forEach(function (button) {
      if (button.getAttribute("aria-pressed") === "true") { active.push(button.getAttribute("data-subject")); }
    });
    return active;
  }

  function itemVisible(item) {
    var active = currentSubjects();
    return active.length === 0 || active.indexOf(item.subject) !== -1;
  }

  function fillItem(item) {
    var figure = el("figure", "gallery-item swiper-slide");
    figure.setAttribute("data-subject", item.subject);
    var caption = el("figcaption", "gallery-caption", item.caption || item.subject);
    if (item.kind === "film") {
      var video = document.createElement("video");
      video.className = "gallery-media";
      video.src = item.src;
      if (item.poster) { video.poster = item.poster; }
      video.muted = true;
      video.loop = true;
      video.playsInline = true;
      video.preload = "none";
      video.setAttribute("playsinline", "");
      video.controls = true;
      video.setAttribute("aria-label", item.caption || item.subject + " film");
      figure.appendChild(video);
      figure.classList.add("is-film");
    } else {
      var image = document.createElement("img");
      image.className = "gallery-media";
      image.src = item.src;
      image.alt = item.caption || item.subject + " still";
      image.loading = "lazy";
      image.decoding = "async";
      figure.appendChild(image);
    }
    figure.appendChild(caption);
    return figure;
  }

  function rebuild() {
    while (track.firstChild) { track.removeChild(track.firstChild); }
    var items = (manifest && manifest.items ? manifest.items : []).filter(itemVisible);
    items.forEach(function (item) { track.appendChild(fillItem(item)); });
    if (empty) { empty.hidden = items.length > 0; }
    say(items.length + " of " + (manifest && manifest.items ? manifest.items.length : 0) + " items shown");
    if (swiper && swiper.update) { swiper.update(); }
  }

  function buildFilter() {
    if (!filterBox) { return; }
    var all = el("button", "subject-chip is-active", "all");
    all.type = "button";
    all.setAttribute("data-subject", "all");
    all.setAttribute("aria-pressed", "true");
    filterBox.appendChild(all);
    var subjects = (manifest && manifest.subjects) || [];
    subjects.forEach(function (subject) {
      var chip = el("button", "subject-chip", subject);
      chip.type = "button";
      chip.setAttribute("data-subject", subject);
      chip.setAttribute("aria-pressed", "false");
      filterBox.appendChild(chip);
    });
    filterBox.addEventListener("click", function (event) {
      var button = event.target.closest("button[data-subject]");
      if (!button) { return; }
      var subject = button.getAttribute("data-subject");
      if (subject === "all" || currentSubjects().length === 0) {
        filterBox.querySelectorAll("button[data-subject]").forEach(function (chip) {
          chip.setAttribute("aria-pressed", subject === "all" || chip === button ? "true" : "false");
        });
      } else {
        button.setAttribute("aria-pressed", button.getAttribute("aria-pressed") === "true" ? "false" : "true");
        if (currentSubjects().length === 0) {
          var allChip = filterBox.querySelector('button[data-subject="all"]');
          if (allChip) { allChip.setAttribute("aria-pressed", "true"); }
        } else {
          var allChip2 = filterBox.querySelector('button[data-subject="all"]');
          if (allChip2) { allChip2.setAttribute("aria-pressed", "false"); }
        }
      }
      rebuild();
    });
  }

  function initRail() {
    if (window.Swiper && rail.classList.contains("swiper")) {
      swiper = new window.Swiper(rail, {
        slidesPerView: "auto",
        spaceBetween: 12,
        keyboard: { enabled: true, onlyInViewport: true },
        navigation: { nextEl: next, prevEl: prev },
        a11y: { enabled: true },
        watchOverflow: true
      });
    } else {
      rail.classList.add("no-swiper");
      if (prev) { prev.addEventListener("click", function () { nudge(-1); }); }
      if (next) { next.addEventListener("click", function () { nudge(1); }); }
    }
  }

  function nudge(direction) {
    var slide = track.firstElementChild;
    var step = slide ? slide.getBoundingClientRect().width + 12 : 320;
    rail.scrollBy({ left: direction * step, behavior: "smooth" });
  }

  function initFit() {
    if (!fitToggle) { return; }
    fitToggle.addEventListener("click", function () {
      var fill = fitToggle.getAttribute("data-fit") === "fit";
      fitToggle.setAttribute("data-fit", fill ? "fill" : "fit");
      fitToggle.textContent = fill ? "fill" : "fit";
      fitToggle.setAttribute("aria-pressed", fill ? "true" : "false");
      document.body.classList.toggle("gallery-fill", fill);
    });
  }

  function initBed() {
    if (!bedToggle) { return; }
    bedToggle.addEventListener("click", function () {
      if (!window.Audio) { say("This browser cannot play the bed."); return; }
      if (!bed) {
        bed = new window.Audio(bedToggle.getAttribute("data-bed-src"));
        bed.loop = true;
        bed.preload = "none";
      }
      if (bed.paused) {
        var played = bed.play();
        if (played && played.then) {
          played.then(function () {
            bedToggle.textContent = "bed: on";
            bedToggle.setAttribute("aria-pressed", "true");
          }, function () {
            say("The dilla bed could not start. The file lives beside the page and stays out of git.");
          });
        }
      } else {
        bed.pause();
        bedToggle.textContent = "bed: off";
        bedToggle.setAttribute("aria-pressed", "false");
      }
    });
  }

  if (!manifest) {
    if (empty) { empty.hidden = false; }
    say("No manifest loaded. Build it with ruby STUDIO/lora/selfies_gallery.rb.");
  } else {
    buildFilter();
    rebuild();
    say((manifest.count || 0) + " stills, " + ((manifest.items || []).length - (manifest.count || 0)) + " films");
  }
  initRail();
  initFit();
  initBed();
})();
