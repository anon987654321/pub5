# frozen_string_literal: true

require "json"
require_relative "pixel_match"

module Fix
  module Visual
    # Each declared component in every state, mobile first (pub4
    # 1e939c7f8b; BackstopJS's scenario list without its runtime): component
    # x state x width x zoom x locale x scheme, cut at cells_per_component so
    # a pass stays bounded, each cell a clipped shot over the DOM session,
    # tiled into one composite a component. A must-differ state identical to
    # its default is FOCUS_VISIBLE; a component overflowing its box or the
    # viewport is INTRINSIC_LAYOUT.
    module StateMatrix
      MOBILE_MAX = 767
      PAD = 8
      COLUMNS = 4
      CELLS = 12
      DEFAULT = { "widths" => [390, 360, 320, 768, 1024, 1440, 1920], "zoom" => { "width" => 1280, "factor" => 2 },
                  "states" => %w[hover focus-visible active disabled loading error empty long-text],
                  "locales" => %w[nb en], "schemes" => %w[light dark], "must_differ" => %w[focus-visible] }.freeze
      LOCALES = { "nb" => "nb-NO,nb;q=0.9", "en" => "en-US,en;q=0.9" }.freeze
      PSEUDO = { "hover" => %w[hover], "focus-visible" => %w[focus focus-visible], "active" => %w[active] }.freeze
      SCRIPTED = {
        "disabled" => "el.disabled = true; el.setAttribute('aria-disabled', 'true');",
        "loading" => "el.setAttribute('aria-busy', 'true');",
        "error" => "el.setAttribute('aria-invalid', 'true');",
        "empty" => "el.textContent = '';",
        "long-text" => "el.textContent = 'Langtekst for et smalt felt '.repeat(6);"
      }.freeze
      RECT_JS = <<~'JS'
        ((selector) => {
          const el = document.querySelector(selector);
          if (!el) return null;
          el.scrollIntoView({ block: "center" });
          const r = el.getBoundingClientRect();
          return { x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height,
                   overflow: el.scrollWidth > el.clientWidth + 1 || r.right > innerWidth + 1 || r.left < -1 };
        })(__SELECTOR__)
      JS

      Cell = Data.define(:state, :width, :scale, :locale, :scheme) do
        def height = width <= MOBILE_MAX ? 844 : 900
        def label = "#{state} #{width}px#{" x#{scale}" if scale > 1} #{locale} #{scheme}"
        def twin = with(state: "default")

        def emulate(session, url)
          session.viewport(width, height, mobile: width <= MOBILE_MAX, scale:)
          session.command("Emulation.setEmulatedMedia", features: [{ name: "prefers-color-scheme", value: scheme }])
          session.headers("Accept-Language" => LOCALES.fetch(locale, locale))
          session.navigate(url)
        end
      end

      Target = Data.define(:url, :selector) do
        def apply(session, state)
          return session.force_pseudo_state(selector, PSEUDO.fetch(state)) if PSEUDO.key?(state)
          return unless SCRIPTED.key?(state)

          session.evaluate("((el) => { if (el) { #{SCRIPTED.fetch(state)} } })(document.querySelector(#{selector.to_json}))")
        end

        def release(session, state) = PSEUDO.key?(state) && session.force_pseudo_state(selector, [])
        def rect(session) = session.evaluate(RECT_JS.sub("__SELECTOR__") { selector.to_json })
      end

      module_function

      # Default and every state at the first width, then the other widths,
      # then the zoom, the second locale and the dark scheme.
      def plan(config = DEFAULT, cap: CELLS)
        first, *others = config.fetch("widths")
        base = Cell.new(state: "default", width: first, scale: 1, locale: config["locales"].first, scheme: config["schemes"].first)
        zoom = config["zoom"]
        variants = (zoom ? [base.with(width: zoom["width"] / zoom["factor"], scale: zoom["factor"])] : []) +
                   config["locales"].drop(1).map { |locale| base.with(locale:) } +
                   config["schemes"].drop(1).map { |scheme| base.with(scheme:) }
        [base, *config["states"].map { |state| base.with(state:) }, *others.map { |width| base.with(width:) }, *variants].first(cap)
      end

      def capture(session, target, cells:)
        cells.filter_map do |cell|
          cell.emulate(session, target.url)
          target.apply(session, cell.state)
          rect = target.rect(session) or next
          shot = session.screenshot(clip: clip(rect))
          target.release(session, cell.state)
          { cell:, rect:, overflow: rect["overflow"], shot: }
        end
      end

      def clip(rect)
        { x: [rect["x"].to_f - PAD, 0].max, y: [rect["y"].to_f - PAD, 0].max,
          width: [rect["w"].to_f + (2 * PAD), 1].max, height: [rect["h"].to_f + (2 * PAD), 1].max }
      end

      def judge(component, rows, must_differ: DEFAULT["must_differ"])
        shots = rows.to_h { |row| [row[:cell], row[:shot]] }
        unseen = rows.filter_map do |row|
          twin = shots[row[:cell].twin]
          next unless must_differ.include?(row[:cell].state) && twin && same?(twin, row[:shot])

          "state_matrix unseen_state: #{component} #{row[:cell].label} renders identically to default law=FOCUS_VISIBLE"
        end
        unseen + rows.select { |row| row[:overflow] }.map do |row|
          "state_matrix overflow: #{component} #{row[:cell].label} overflows its box or the viewport law=INTRINSIC_LAYOUT"
        end
      end

      def same?(one, two)
        result = PixelMatch.compare(one, two)
        result[:status] == :compared && result[:pixel_diff_count].zero?
      end

      # The cells tiled COLUMNS to a row on white, each in a slot the size of the largest; PNG bytes.
      def composite(rows)
        frames = rows.map { |row| PixelMatch.read(row[:shot]) }
        slot = [frames.map(&:width).max, frames.map(&:height).max]
        width = slot[0] * [COLUMNS, frames.size].min
        height = slot[1] * frames.size.fdiv(COLUMNS).ceil
        canvas = Array.new(width * height, 0xffffffff)
        frames.each_with_index do |frame, index|
          left = (index % COLUMNS) * slot[0]
          top = (index / COLUMNS) * slot[1]
          frame.lines.each_with_index { |pixels, line| canvas[((top + line) * width) + left, pixels.size] = pixels }
        end
        Png.encode(width, height, canvas.pack("N*"))
      end
    end

    # axe-core run inside the page over the DOM session (pub4 7cdc4cb290),
    # each violated rule mapped onto the Law that owns it; a rule no Law owns
    # is law=unmapped, never dropped. axe.min.js (MPL-2.0) is read from where
    # the caller keeps it; it is not vendored here yet.
    module Axe
      LAWS = {
        "IMG_ALT" => %w[image-alt input-image-alt role-img-alt svg-img-alt area-alt object-alt],
        "FORM_LABEL" => %w[label label-title-only select-name form-field-multiple-labels],
        "ARIA_LABELS" => %w[button-name link-name aria-command-name aria-input-field-name aria-toggle-field-name
                            aria-meter-name aria-progressbar-name aria-tooltip-name aria-dialog-name frame-title],
        "ARIA_INTERACTIVE" => %w[aria-allowed-attr aria-allowed-role aria-required-attr aria-required-children
                                 aria-required-parent aria-roles aria-valid-attr aria-valid-attr-value
                                 aria-hidden-focus aria-prohibited-attr],
        "INTERACTION_SEMANTICS" => %w[nested-interactive scrollable-region-focusable focus-order-semantics tabindex],
        "HTML_HEADING_HIERARCHY" => %w[heading-order page-has-heading-one empty-heading],
        "CONTRAST_TOKENS" => %w[color-contrast color-contrast-enhanced link-in-text-block],
        "TOUCH_TARGET_MIN" => %w[target-size],
        "MOBILE_ACCESSIBILITY_DEFAULTS" => %w[meta-viewport meta-viewport-large html-has-lang html-lang-valid
                                              landmark-one-main region bypass document-title]
      }.freeze
      RULE_LAW = LAWS.flat_map { |law, rules| rules.map { |rule| [rule, law] } }.to_h.freeze
      RUN_JS = <<~'JS'
        axe.run(document, { resultTypes: ["violations"] }).then((r) => JSON.stringify({
          violations: r.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length,
                                                 target: (v.nodes[0] && v.nodes[0].target.join(" ")) || "" })),
          incomplete: r.incomplete.length
        }))
      JS

      module_function

      def run(session, source:)
        session.evaluate(source) unless session.evaluate("typeof window.axe === 'object'")
        JSON.parse(session.evaluate(RUN_JS, await_promise: true).to_s)
      end

      def law(rule) = RULE_LAW.fetch(rule, "unmapped")

      def findings(label, report)
        Array(report["violations"]).map do |row|
          "accessibility_axe: #{label} #{row['id']} x#{row['nodes']} (#{row['impact']}) - #{row['target']} law=#{law(row['id'])}"
        end
      end
    end
  end
end
