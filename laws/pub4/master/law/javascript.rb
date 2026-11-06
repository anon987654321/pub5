# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0ed868a8fd2f5adf
require_relative "../lib/master"

# law/javascript.rb — every javascript law, one Law.define per law.








# CONST_BY_DEFAULT lives once, in the registry (js_rules.rb): it reads the
# rest of the file to ask whether the variable is ever reassigned before it
# calls a `let` wrong. This line detector flagged every `let` in the tree,
# including the ones whose reassignment is the reason they are `let`.



































































# The face is a field of pixels, and a pixel has one size. The renderer draws
# into a capped buffer that CSS upscales with image-rendering:pixelated, so one
# fragment is one visible square block — a point that scales with depth or
# curvature stops being a pixel and becomes a blob, and a field of overlapping
# blobs is what made the face read as a lit wireframe mass. Depth, curvature and
# silhouette belong in brightness instead, which is where 1-bit imagery has
# always carried form.










# pixel_perfection bans soft glow in CSS. It was implemented in WebGL instead,
# where the CSS scanner could not see it: a second THREE.Points pass over the
# same geometry at 1.22x size with additive blending, which is a halo by
# construction. It also doubled every vertex and cost ~13 blended fragments per
# particle. The brutalist profile "removed" it by setting the scale to 1.0 —
# which co-sites the pass rather than deleting it, so the face just rendered
# twice as bright. A knob cannot switch off a layer that should not exist.



































module Master
  module Review
    module Scan
      module Laws
        # Retired registry twins — each lives once, in law/:
        #   DOLLAR_PAREN
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        VENDORED_JS_RE = %r{/public/three\.module\.js\z}.freeze

        
























        # NULLISH_COALESCING lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # TEMPLATE_LITERALS lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # ASYNC_AWAIT lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # FOR_OF lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).
        




























































        














        # NO_VAR lives once, in law/javascript.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        














        # STIMULUS_CONTROLLER_SIZE lives in surface_rules.rb with the rest of the
        # STIMULUS_* family; the copy that stood here was a duplicate registration of
        # the same id (SINGULARITY) and double-counted every hit — test_rule_ids_unique.

      # A02 MAGIC_COLOR — raw color values must reference design tokens (MAGIC_COLOR).
      #
      # Before trying to fix these in bulk, read this. It has been measured twice,
      # from two directions, and the answer both times was that there is no
      # mechanical substitution available in this repo.
      #
      # A substitution is only safe if it preserves the rendered value. The tokens
      # whose values match the commonest literals — --bg, --surface, --border,
      # --search-bg — are theme-responsive: _dialect_tokens.scss defines them
      # inside @mixin brgen-old-dark-tokens and @mixin brgen-old-light-tokens, and
      # brgen includes both, under different selectors. So `--bg` is #000000 in
      # dark and #ffffff in light *within one app*. A literal is theme-independent
      # by construction; swapping it for the token makes it follow the theme,
      # which changes the other theme. That is a behaviour change wearing the
      # clothes of a lint fix.
      #
      # Scoping per app does not rescue it: brgen defines four single-valued
      # tokens of its own and no remaining literal equals any of them.
      #
      # So the question each finding actually asks is not "which token is this" —
      # it is "should this colour follow the theme or not", which only the person
      # who chose it can answer. Six passes over this rule removed 596 findings
      # and every one was the rule misreading something; none was a substitution.
        









































































      # A11 OPTIONAL_CHAINING_JS — && guard chains in JavaScript (OPTIONAL_CHAINING).
        









      end
    end
  end
end

# Gestures, motion, charts and orientation (WCAG 2.5.1/2.5.7, 2.2.2, 1.3.4; Tufte; Clark). Their
# rendered halves are adapters over a design_laws snapshot (Deploy::RenderedDesign).
require_relative "../checks/support/rendered_design"

module Law
  module Script
    SNAP = Deploy::RenderedDesign
    POINTER = /touch(?:start|move|end)|pointer(?:down|move|up)/
    GESTURE = /["']#{POINTER}["']|#{POINTER}->|swipe/i
    HANDLER = /\A(?:connect|disconnect|initialize|on\w*|handle\w*|\w*(?:touch|pointer|swipe|drag|start|move|end)\w*)\z/i

    MOVES = /\.style\.transform|scroll(?:Left|To|By)\(|\bslide|carousel|\.next\(\)|advance\(/i
    ENDLESS = /animation(?:-iteration-count)?\s*:[^;}]*\binfinite\b/
    QUIET_LOOPS = /spin|load|busy|progress|pending/i
    TIMER = /setInterval\(/
    CHART_FAULTS = {
      /beginAtZero:\s*false/ => "the value axis does not start at zero (lie factor)",
      /rotate3d|matrix3d|rotate[XY]\(|perspective\(/ => "a chart drawn in perspective",
      /(?:grid|gridLines)\s*:\s*\{[^}]*lineWidth:\s*[2-9]/ => "gridlines heavier than a hairline",
    }.freeze
    LOCKED = /"orientation"\s*:\s*"(?!any"|natural")|screen\.orientation\.lock\(/

    module_function

    METHOD = /^\s{2}(?:async\s+)?(\w+)\s*\([^)]*\)\s*\{/

    # Each method's name and body, cut at the next method definition.
    def methods_of(src)
      starts = src.to_enum(:scan, METHOD).map { [Regexp.last_match(1), Regexp.last_match.begin(0)] }
      starts.each_with_index.to_h { |(name, at), index| [name, src[at...(starts[index + 1]&.last || src.size)]] }
    end

    # Methods a gesture handler calls on itself that are results, not more handling.
    def results(src)
      bodies = methods_of(src)
      called = bodies.select { |name, _body| name.match?(HANDLER) }.values.join.scan(/this\.(\w+)\(/).flatten.uniq
      called.select { |name| bodies.key?(name) && !name.match?(HANDLER) }
    end

    def views(path)
      root = path.to_s[%r{\A.*?/(?:RAILS/[^/]+|MASTER/web)(?=/)}] or return ""
      (@views ||= {})[root] ||= Dir[File.join(root, "**/*.erb")].sum("") { |file| File.read(file) }
    end

    def tapped?(src, path:, action:)
      controller = File.basename(path.to_s, "_controller.js").tr("_", "-")
      wired = /(?:click|submit|keydown[\w.]*)->#{Regexp.escape(controller)}##{action}\b/
      listened = src.match?(/addEventListener\(\s*["'](?:click|keydown)["'][^\n]*this\.#{action}\b/)
      listened || "#{src}\n#{views(path)}".match?(wired)
    end

    def untapped(src, path)
      return [] unless src.match?(GESTURE)

      results(src).reject { |action| tapped?(src, path:, action:) }.map do |action|
        { line: line_of(src, /this\.#{action}\(/), message: "gesture result #{action} has no tap control" }
      end
    end

    def rendered(id) = ->(text, file) { SNAP.findings(id, text, file).map { |hit| finding(**hit) } }

    def line_of(src, pattern) = src.lines.index { |line| line.match?(pattern) }.to_i + 1

    def endless(src)
      src.scan(/([^{}]*)\{([^{}]*)\}/).filter_map do |selector, body|
        name = selector.strip
        next unless body.match?(ENDLESS) && !name.match?(QUIET_LOOPS)

        { line: line_of(src, /#{Regexp.escape(name)}\s*\{/), message: "#{name} animates forever with no pause" }
      end
    end

    def chart_fault(line) = CHART_FAULTS.find { |pattern, _message| line.match?(pattern) }&.last

    def motion(changes)
      { "probe" => "design_laws", "motion" => { "changes" => changes, "last_change" => changes * 150 } }.to_json
    end

    def stack(*actions)
      SNAP.fixture(elements: actions.map { |action| SNAP.element("div", attrs: { "data-action" => action }) })
    end

    def controller(*extra)
      ["export default class extends Controller {",
       "  connect() { this.element.addEventListener(\"touchend\", (e) => this.end(e)) }",
       *extra, "  end(e) { if (this.dx > 60) this.like() }", "  like() { this.element.remove() }", "}", ""].join("\n")
    end
  end

  S = Script

  













  




















  

















  















end
