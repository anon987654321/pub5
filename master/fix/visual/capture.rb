# frozen_string_literal: true

require "json"

module Fix
  module Visual
    # What a pass renders, phones first (pub4 cf0d9831e1, operator
    # 2026-11-06): 390 wide, then 360, then 320, then every wider viewport by
    # width. A pass renders a bounded share (pub4 28a48c6e7d: all 212
    # surfaces took 13 minutes a pass): mobile captures rotated by pass so
    # consecutive passes reach every one, and a desktop capture only with room
    # left after every mobile one, so desktop is what the cap cuts.
    module Surfaces
      MOBILE = [390, 360, 320].freeze
      MOBILE_MAX = 767
      WIDTHS = [*MOBILE, 1280].freeze
      CAP = 24
      Surface = Data.define(:app, :path, :port, :width) do
        def id = "#{app}#{path.tr('/', '_')}-#{width}"
        def height = width <= MOBILE_MAX ? 844 : 900
        def mobile? = width <= MOBILE_MAX
        def url = "http://127.0.0.1:#{port}#{path}"
      end

      module_function

      def for_apps(apps, paths: ["/"]) = apps.product(paths, WIDTHS).map { |app, path, width| Surface.new(app: app.name, path:, port: app.port, width:) }

      def mobile_first(rows)
        rows.each_with_index.sort_by { |s, i| [s.mobile? ? 0 : 1, MOBILE.index(s.width) || MOBILE.size, s.width, i] }.map(&:first)
      end

      def select(rows, pass:, cap: CAP)
        mobile, wide = mobile_first(rows).partition(&:mobile?)
        return mobile + wide if cap <= 0

        shown = rotated(mobile, cap, pass)
        shown + rotated(wide, cap - shown.size, pass)
      end

      def rotated(rows, room, pass)
        return [] if room <= 0
        return rows if rows.size <= room

        mobile_first(rows.rotate(((pass - 1) * room) % rows.size).first(room))
      end
    end

    # A screenshot that holds still before a baseline judges it (pub4
    # da2fb285e8, Playwright toHaveScreenshot's recipe): animations and
    # transitions stopped, the caret hidden, declared volatile regions covered
    # by a solid box, fonts settled, then shots retaken until two in a row are
    # byte-identical. A page that never holds still is UNSTABLE: not compared.
    module Still
      ATTEMPTS = 4
      FREEZE_JS = <<~'JS'
        ((selectors) => {
          const style = document.createElement("style");
          style.textContent = "*,*::before,*::after{animation-duration:0s!important;animation-delay:0s!important;" +
            "transition-duration:0s!important;transition-delay:0s!important;caret-color:transparent!important}";
          document.head.appendChild(style);
          for (const run of document.getAnimations()) {
            const t = run.effect && run.effect.getComputedTiming();
            if (t && t.endTime === Infinity) run.cancel(); else run.finish();
          }
          let masked = 0;
          for (const el of document.querySelectorAll(selectors.join(",") || ":not(*)")) {
            const r = el.getBoundingClientRect();
            if (r.width < 1 || r.height < 1) continue;
            const box = document.createElement("div");
            box.style.cssText = `position:absolute;left:${r.left + scrollX}px;top:${r.top + scrollY}px;` +
              `width:${r.width}px;height:${r.height}px;background:#ff00ff;z-index:2147483647;pointer-events:none`;
            document.body.appendChild(box);
            masked += 1;
          }
          return masked;
        })(__SELECTORS__)
      JS
      FONTS_JS = "document.fonts.ready.then(() => true)"

      module_function

      # session: anything answering evaluate(js, await_promise:) and screenshot -> PNG bytes.
      def shot(session, mask: [])
        masked = session.evaluate(FREEZE_JS.sub("__SELECTORS__") { Array(mask).to_json })
        session.evaluate(FONTS_JS, await_promise: true)
        settle(-> { session.screenshot }).merge(masked:)
      end

      # Retakes until two shots in a row agree: { png:, attempts:, stable: }.
      def settle(take, attempts: ATTEMPTS)
        previous = nil
        (1..attempts).each do |attempt|
          bytes = take.call
          return { png: bytes, attempts: attempt, stable: true } if bytes == previous

          previous = bytes
        end
        { png: previous, attempts:, stable: false }
      end
    end

    # A camera with no DOM session: headless Chrome through World#exec, one
    # --screenshot a shot, held still by retaking until two agree.
    class Headless
      def initialize(world:, chrome:, dir: "tmp/fix/visual/shots")
        @world = world
        @chrome = chrome
        @dir = dir
      end

      def available? = @chrome && File.executable?(@chrome)

      def capture(surface)
        path = File.join(@dir, "#{surface.id}.png")
        Still.settle(lambda {
          run = @world.exec(@chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                            "--screenshot=#{File.join(@world.manifest.root, path)}", "--window-size=#{surface.width},#{surface.height}",
                            surface.url, timeout: 60)
          run.ok? ? @world.read(path) : nil
        })
      end
    end
  end
end
