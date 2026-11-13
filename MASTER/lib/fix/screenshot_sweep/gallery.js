// The gallery's carousel. The rail is a native scroll-snap strip, so touch
// swipe and a no-JS reader already work; this adds the arrows, the dots, and
// the arrow keys on a focused rail. Nothing here loads from the network.
(() => {
  const strips = document.querySelectorAll("[data-strip]");
  strips.forEach(setup);

  function setup(rail) {
    const strip = rail.closest(".strip");
    const slides = Array.from(rail.querySelectorAll(".slide"));
    if (!strip || slides.length === 0) return;

    // Marked scripted so the stylesheet reveals the arrows and dots it hides
    // by default; a reader without this keeps a plain scroll-snap rail.
    strip.setAttribute("data-scripted", "");

    const prev = strip.querySelector('[data-step="-1"]');
    const next = strip.querySelector('[data-step="1"]');
    const dots = strip.querySelector("[data-dots]");
    const marks = slides.map((_, index) => {
      const dot = document.createElement("button");
      dot.type = "button";
      dot.setAttribute("aria-label", `Screenshot ${index + 1} of ${slides.length}`);
      dot.addEventListener("click", () => go(index));
      if (dots) dots.appendChild(dot);
      return dot;
    });

    function stride() {
      if (slides.length > 1) return slides[1].offsetLeft - slides[0].offsetLeft;
      return slides[0].getBoundingClientRect().width;
    }

    function current() {
      const step = stride();
      return step ? Math.round(rail.scrollLeft / step) : 0;
    }

    function go(index) {
      const clamped = Math.max(0, Math.min(slides.length - 1, index));
      rail.scrollTo({ left: clamped * stride(), behavior: "smooth" });
    }

    function sync() {
      const index = current();
      if (prev) prev.disabled = index <= 0;
      if (next) next.disabled = index >= slides.length - 1;
      marks.forEach((mark, n) => mark.setAttribute("aria-current", String(n === index)));
    }

    if (prev) prev.addEventListener("click", () => go(current() - 1));
    if (next) next.addEventListener("click", () => go(current() + 1));
    rail.addEventListener("keydown", (event) => {
      if (event.key === "ArrowRight") {
        event.preventDefault();
        go(current() + 1);
      } else if (event.key === "ArrowLeft") {
        event.preventDefault();
        go(current() - 1);
      }
    });

    let ticking = false;
    rail.addEventListener("scroll", () => {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        ticking = false;
        sync();
      });
    }, { passive: true });
    window.addEventListener("resize", sync);
    sync();
  }
})();
