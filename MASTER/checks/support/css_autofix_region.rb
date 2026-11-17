# frozen_string_literal: true

module Deploy
  # The one owner of the generated-autofix region shapes.
  #
  # GeometryAutofix and KansoAutofix both append a marker-delimited region to
  # an app's entry stylesheet, and CssNoImportantCheck plus CssLayerStackCheck
  # both need to find and read those regions. Markers defined here are the
  # single definition the writers and the readers share; a region shape that
  # changes changes here or not at all.
  #
  # Layer placement follows data/css_architecture.yml#cascade_layers.rules:
  # a wrapped region - `@layer autofix { ... }` between the markers - is what
  # a stack-declared entry must carry, while an entry whose author CSS is
  # still unlayered carries the region bare. Unlayered normal declarations
  # beat layered ones, so wrapping before the author CSS is layered would
  # demote every generated fix below the rule it exists to beat. Writers ask
  # stack_declared? at write time; the layer-stack check holds the same
  # predicate against files at read time.
  module CssAutofixRegion
    LAYER = "autofix"

    GEOMETRY_OPEN = "// Deploy::GeometryAutofix begin - generated, do not hand-edit"
    GEOMETRY_CLOSE = "// Deploy::GeometryAutofix end"

    # Kanso's findings stay human-judged for now (upstream's KansoSurfaceCheck
    # writes nothing), so GeometryAutofix is the only region writer. A second
    # writer joins here, with its own markers, the day one lands.
    REGIONS = [[GEOMETRY_OPEN, GEOMETRY_CLOSE]].freeze

    # An order statement (`@layer a, b, c;`) - names and a semicolon, never a
    # block. A block form at depth 0 is a named layer, not an order statement.
    ORDER_STATEMENT = /^\s*@layer\s+[^;{}]*;\s*$/.freeze

    module_function

    def stack_declared?(source)
      source.match?(ORDER_STATEMENT)
    end

    # The region body as it must land in this entry: wrapped in the autofix
    # layer when the entry declares the stack, bare otherwise.
    def wrap(block, source)
      return block unless stack_declared?(source)

      "@layer #{LAYER} {\n#{block}}\n"
    end

    # Region text back to its rule shape, so a row parser reads the same
    # lines whether the stored region is layered or bare. Only a real wrapper
    # is stripped: a bare region that happens to end in a rule's own `}` must
    # come back whole, or the last rule loses its brace and every row parser
    # after it goes blind.
    def unwrap(block)
      return block unless wrapped?(block)

      block.sub(/\A@layer #{LAYER} \{\n/, "").sub(/\}\n\z/, "")
    end

    # Inner text of every marker-delimited region in the source, wrapped or
    # not, with the wrapper lines intact (readers that want rules run unwrap).
    def region_bodies(source)
      REGIONS.filter_map do |open, close|
        source[/^#{Regexp.escape(open)}\n(.*?)^#{Regexp.escape(close)}\n?/m, 1]
      end
    end

    # Whether the region text carries the layer wrapper.
    def wrapped?(block)
      block.start_with?("@layer #{LAYER} {")
    end
  end
end
