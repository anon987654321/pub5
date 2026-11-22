# frozen_string_literal: true

require "json"
require_relative "../../support/check_result"
require_relative "../../../lib/gap"
require_relative "../../../lib/master/density"
require_relative "../../support/geometry_probe"
require_relative "../../support/crawl_support"

module Deploy
  # Kanso proxies on public surfaces, measured in a real browser.
  #
  # The geometry walk deliberately skips everything that carries no text, no
  # interactivity, and no landmark — the right filter for Fitts and contrast,
  # and the reason a decorative wrapper is invisible to it by construction.
  # This leaf runs its own kanso probe below, which walks the same DOM with
  # the opposite question, and hands the payload to Master::Density, whose
  # findings name the DENSITY_kanso* Law ids.
  #
  # Every finding is soft on purpose. The proxies (shadow-only chrome,
  # content-free nesting, off-scale residual gaps, the painted-area envelope)
  # are uncalibrated: a full sweep on the declared surfaces tunes them, and
  # CHECK_STRICT_SOFT=1 is how a run promotes them before the Laws do.
  #
  # The two automatic-resolution children have detector proof fixtures
  # (MASTER/test/test_kanso_laws.rb); no mechanical pen exists yet — the
  # findings describe what earns removal, nothing is rewritten here.
  class KansoSurfaceCheck
    ROOT = File.expand_path("../../../..", __dir__)

    def self.run = new.run

    # The kanso walk. Measures what GeometryProbe::WALK cannot see: WALK
    # records only elements that carry text, interactivity, or a landmark
    # tag, so a decorative wrapper is invisible to it by construction. A leaf
    # local heredoc, like ViewportSpillCheck::PROBE — this probe has exactly
    # one consumer, and a file of its own is one more path the sprawl census
    # prices. Self-contained: no helper injection, one evaluation per
    # surface, returns a JSON string; everything downstream is computed in
    # Ruby by Master::Density.
    #
    # All counts are first-screen unless a rule says otherwise: kanso is
    # judged on what a visitor actually sees before scrolling.
    PROBE = <<~JS
      (() => {
        const MAX = 2000;
        const de = document.documentElement;
        const vw = de.clientWidth;
        const vh = de.clientHeight;
        const viewportArea = Math.max(1, vw * vh);

        const INTERACTIVE_SEL = [
          'a[href]', 'button', 'input:not([type=hidden])', 'select', 'textarea',
          'summary', '[role]', '[onclick]', '[tabindex]:not([tabindex="-1"])', '[aria-label]'
        ].join(',');
        const MEDIA_SEL = 'img, svg, video, audio, canvas, picture, iframe, object, embed';
        // Tags that carry hierarchy by existing; nesting through them is
        // document structure, not clutter, even when they wrap a single child.
        const HIERARCHY_SEL = 'header, nav, main, footer, aside, section, article, form, ' +
          'h1, h2, h3, h4, h5, h6, ul, ol, li, table, thead, tbody, tr, td, th, figure, ' +
          'blockquote, p, label, fieldset, dl, dt, dd, hr, br';
        const LEAF_MEDIA_SEL = 'img, video, canvas, iframe, object, embed, svg';

        const ownTextOf = (el) => Array.from(el.childNodes)
          .filter((n) => n.nodeType === 3)
          .map((n) => n.textContent.trim())
          .join(' ')
          .trim();

        // Same selector-key shape as walk.js, so a kanso finding names the
        // same component a geometry finding would.
        const VOLATILE_CLASS = /^(ng-|js-|is-|has-|turbo-|network-|battery-|power-)|(-|^)(connected|disconnected|loading|loaded|ready|active|open|closed|revealed|hidden|visible|scrolled|pending|selected|next|prev|duplicate)$/;
        const classSig = (el) => {
          const cls = (el.getAttribute('class') || '').trim().split(/\\s+/)
            .filter((c) => c && !VOLATILE_CLASS.test(c)).slice(0, 2);
          return cls.length ? '.' + cls.join('.') : '';
        };
        const selFor = (el) => {
          if (el.id) return '#' + el.id;
          const parts = [];
          let node = el;
          let depth = 0;
          while (node && node.nodeType === 1 && depth < 4) {
            if (node.id) { parts.unshift('#' + node.id); break; }
            parts.unshift(node.tagName.toLowerCase() + classSig(node));
            node = node.parentElement;
            depth++;
          }
          return parts.join('>');
        };
        const seen = Object.create(null);
        const keyFor = (sel) => {
          seen[sel] = (seen[sel] || 0) + 1;
          return seen[sel] === 1 ? sel : sel + '[' + seen[sel] + ']';
        };

        const onscreen = (r) => r.right > 0 && r.left < vw && r.bottom > 0 && r.top < vh;

        // Does this element paint anything its own box is responsible for? A
        // background, a border edge, a shadow, a gradient, or a filter.
        const paints = (cs) => {
          const bg = cs.backgroundColor;
          const hasBg = bg && bg !== 'transparent' && bg !== 'rgba(0, 0, 0, 0)';
          const hasBorder = ['Top', 'Right', 'Bottom', 'Left']
            .some((side) => parseFloat(cs['border' + side + 'Width']) > 0);
          return hasBg || hasBorder || cs.boxShadow !== 'none' ||
            (cs.backgroundImage && cs.backgroundImage !== 'none' && /gradient\\(/i.test(cs.backgroundImage)) ||
            (cs.filter && cs.filter !== 'none');
        };

        // Whole-subtree content test: no text nodes, no controls, no media
        // anywhere below. The element itself may nest arbitrarily deep.
        const subtreeHasContent = (el) => {
          if (ownTextOf(el)) return true;
          if (el.matches(INTERACTIVE_SEL)) return true;
          if (el.querySelector(INTERACTIVE_SEL + ',' + MEDIA_SEL)) return true;
          const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
          while (walker.nextNode()) {
            if (walker.currentNode.textContent.trim()) return true;
          }
          return false;
        };

        // A pass-through container: no own text, no semantics of its own,
        // exactly one visible element child, and the content lives deeper.
        // One level is component structure; the chain length is what clutter
        // looks like.
        const isPassthrough = (el) => {
          if (el.matches(HIERARCHY_SEL) || el.matches(INTERACTIVE_SEL)) return false;
          if (el.getAttribute('role') || el.getAttribute('aria-label')) return false;
          if (ownTextOf(el)) return false;
          if (el.querySelector(LEAF_MEDIA_SEL)) return false;
          const kids = Array.from(el.children).filter((k) => {
            const kcs = getComputedStyle(k);
            return kcs.display !== 'none' && kcs.visibility !== 'hidden';
          });
          return kids.length === 1 && !ownTextOf(kids[0]);
        };

        const chains = [];
        const deadRegions = [];
        const shadowChrome = [];
        const ornamentPseudo = [];
        const zSet = new Set();
        let paintedArea = 0;
        let focalArea = 0;
        let contentFreeArea = 0;

        const all = document.querySelectorAll('body *');
        for (let i = 0; i < all.length && i < MAX; i++) {
          const el = all[i];
          const cs = getComputedStyle(el);
          if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0) continue;
          const r = el.getBoundingClientRect();
          if (r.width === 0 || r.height === 0) continue;

          const area = r.width * r.height;
          const first = onscreen(r);
          const tag = el.tagName.toLowerCase();
          const ownText = ownTextOf(el);
          const interactive = el.matches(INTERACTIVE_SEL);
          const media = el.matches(MEDIA_SEL);
          const contentFree = !subtreeHasContent(el);
          const painted = paints(cs);

          if (first) {
            const z = cs.zIndex;
            if (z && z !== 'auto' && parseInt(z, 10) !== 0 && Number.isFinite(parseInt(z, 10))) {
              zSet.add(parseInt(z, 10));
            }
            if (painted || media) paintedArea += area;
            if (contentFree && painted) contentFreeArea += area;
            if ((ownText || interactive || media) && area > focalArea) focalArea = area;
          }

          // Chain top: a passthrough whose parent is NOT one — walk down
          // while the single child stays passthrough, recording depth.
          if (isPassthrough(el)) {
            const parent = el.parentElement;
            const parentIsPassthrough = parent && parent !== document.body &&
              parent !== de && isPassthrough(parent);
            if (!parentIsPassthrough) {
              const levels = [el];
              let node = el.children[0];
              while (node && levels.length < 12 && isPassthrough(node)) {
                levels.push(node);
                node = node.children[0];
              }
              if (levels.length >= 3) {
                const styled = levels.some((lvl) => paints(getComputedStyle(lvl)));
                chains.push({
                  path: levels.map((lvl) => selFor(lvl)).join(' > '),
                  depth: levels.length,
                  styled: styled,
                  dead: contentFree,
                  area: Math.round(r.width) + 'x' + Math.round(r.height),
                });
              }
            }
          }

          if (first && contentFree && painted && tag !== 'hr' && tag !== 'br' && area >= viewportArea * 0.02) {
            deadRegions.push({
              key: keyFor(selFor(el)),
              rect: { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) },
            });
          }

          // Shadow-only chrome: a shadow on a box whose whole subtree carries
          // nothing. A shadow on a content-bearing card is affordance, not ink.
          if (first && contentFree && !interactive && cs.boxShadow !== 'none' && tag !== 'hr' && tag !== 'br') {
            shadowChrome.push({
              key: keyFor(selFor(el)),
              rect: { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) },
              shadow: cs.boxShadow,
            });
          }

          // Ornamental pseudo-element paint: a content-free box whose
          // ::before or ::after has non-none content — the decorative-box
          // idiom. selFor without the seen-counter: the same element twice
          // is one component, not a second instance.
          if (first && contentFree && !interactive && tag !== 'hr' && tag !== 'br') {
            ['::before', '::after'].forEach((pseudo) => {
              const pcs = getComputedStyle(el, pseudo);
              if (pcs.content && pcs.content !== 'none' && pcs.content !== 'normal') {
                ornamentPseudo.push({ key: selFor(el), pseudo: pseudo });
              }
            });
          }
        }

        // Vertical gaps between consecutive major siblings — the same majors
        // the rhythm walk uses, so a kanso gap finding names the same pair a
        // rhythm finding would.
        const gaps = [];
        const containers = document.querySelectorAll('main, main *, [role=main], .feed, .deal-grid');
        for (let i = 0; i < containers.length && gaps.length < 200; i++) {
          const kids = Array.from(containers[i].children).filter((k) => {
            const kcs = getComputedStyle(k);
            if (kcs.display === 'none' || kcs.position === 'absolute' || kcs.position === 'fixed') return false;
            if (kcs.display.startsWith('inline') && !kcs.display.startsWith('inline-')) return false;
            const kr = k.getBoundingClientRect();
            return kr.height > 24 && kr.width > vw * 0.5;
          });
          for (let j = 0; j + 1 < kids.length; j++) {
            const a = kids[j].getBoundingClientRect();
            const b = kids[j + 1].getBoundingClientRect();
            const g = Math.round(b.top - a.bottom);
            if (g >= 4 && g <= 128) {
              gaps.push({ above: selFor(kids[j]), below: selFor(kids[j + 1]), gap: g });
            }
          }
        }

        return JSON.stringify({
          vw: vw,
          vh: vh,
          wrapper_chains: chains.slice(0, 20),
          dead_regions: deadRegions.slice(0, 20),
          shadow_chrome: shadowChrome.slice(0, 12),
          ornament_pseudo: ornamentPseudo.slice(0, 12),
          z_values: Array.from(zSet).sort((a, b) => a - b),
          gaps: gaps,
          painted_area_ratio: Number((paintedArea / viewportArea).toFixed(4)),
          focal_area_ratio: Number((focalArea / viewportArea).toFixed(4)),
          content_free_area_ratio: paintedArea > 0 ? Number((contentFreeArea / paintedArea).toFixed(4)) : 0,
        });
      })()
    JS

    def run
      @result = CheckResult.new
      return unavailable unless GeometryProbe.available?

      surfaces = GeometryProbe.surfaces
      GeometryProbe.unreachable_apps(surfaces).each do |app|
        @result.skipped_live("kanso: #{app} port closed - surfaces skipped")
      end
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.inconclusive!("kanso: no app reachable - nothing measured")
        return @result
      end

      measured = 0
      GeometryProbe.with_browser(root: ROOT, warm: live) do |cdp|
        live.each do |surface|
          measured += 1 if measure(cdp, surface)
        end
      end

      @result.checked!(measured)
      @result.warn("kanso: measured #{measured} surfacexviewport cells")
      @result
    rescue CdpSession::Error => e
      # A browser that will not start measured nothing, and a check that
      # reports nothing measured as a pass is the failure this file exists to
      # prevent.
      @result.inconclusive!("kanso: #{e.class}: #{e.message}")
      @result
    end

    private

    def unavailable
      @result.inconclusive!("kanso: no Chrome, so no surface was measured (set CHROME_PATH)", gap: Master::Gap::NO_BROWSER)
      @result
    end

    # Returns true when the surface was measured, false when it was skipped
    # or its measurement is incomplete — the counter counts evidence, not
    # attempts.
    def measure(cdp, surface)
      unless surface.port && CrawlSupport.port_open?("127.0.0.1", surface.port)
        @result.skipped_live("kanso: #{surface.id} skipped (#{surface.app} not listening)")
        return false
      end

      cdp.viewport(surface.width, surface.height, mobile: surface.width < 500)
      cdp.headers(GeometryProbe::PROBE_HEADERS)
      cdp.clear_cookies
      cdp.navigate(surface.url, settle: 0.8)

      status = cdp.status.to_i
      unless status.zero? || status.between?(200, 399)
        @result.fail("kanso: #{surface.id} served HTTP #{status} at #{surface.url} - clutter not measured " \
                     "(a 403 host-authorization or 500 page is measurable but meaningless)")
        return false
      end
      unless GeometryProbe.wait_for_fonts(cdp, timeout: 3)
        @result.incomplete!("kanso: #{surface.id} font readiness timeout - boxes not measured")
        return false
      end

      payload = JSON.parse(cdp.evaluate(PROBE).to_s)
      findings = Master::Density.kanso(payload, surface: surface.id) +
                 Master::Density.kanso_envelope(payload, surface: surface.id)
      findings.each { |finding| @result.fail(finding[:message], severity: :soft) }
      true
    rescue CdpSession::Error => e
      @result.incomplete!("kanso: #{surface.id} not measured - #{e.message}")
      false
    end
  end
end
