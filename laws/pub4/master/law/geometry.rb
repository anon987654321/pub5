# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/geometry.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 88b82115653619e7
require_relative "../lib/master"

# law/geometry.rb - the type and space Laws the geometry probe already measures, one Law.define
# per law. Each reads the probe's payload (geometry_probe/walk.js, geometry_type_walk.js) saved
# as *.geometry.json, through the SpaceChecks the rendered suite runs (RenderedGeometryCheck
# reports them under these ids), so the page is measured once. TYPEFACE_PER_ROLE also reads
# source: the serif rule Operator::TypographyLint carried now lives here. BPLANS/ is exempt.
require_relative "../checks/support/rendered_design/geometry_laws"

module Law
  # Shared parts of the geometry Laws.
  module GeometryPayload
    G = Deploy::RenderedDesign::GeometryLaws
    SWISS_TREES = %r{RAILS/(?:brgen[^/]*|__shared|amber)/.*\.(?:s?css|erb|html)\z}
    FAMILY = /font-family\s*:\s*([^;}]+)/i
    VENDORED = %w[lightgallery.css].freeze

    module_function

    def declare(law, law_id)
      law.instance_exec(law_id) do |id|
        tags %i[TYPOGRAPHY DESIGN]
        measures :rendered_ui
        example_path G::EXAMPLE
        check(&GeometryPayload.checker(id))
      end
    end

    def checker(id) = ->(text, file) { G.findings(id, text, path: file).map { |hit| finding(**hit) } }

    def box(top, height = 24) = { "x" => 16, "y" => top, "w" => 358, "h" => height }

    def grouped(heading_top)
      heading = G.leaf("h2.section", tag: "h2", frect: box(heading_top, 28))
      G.fixture(elements: [G.leaf("p.intro", frect: box(16, 96)), heading, G.leaf("p.body", frect: box(180, 96))])
    end

    def serif_rows(src, file)
      return [] if VENDORED.include?(File.basename(file.to_s)) || file.to_s.include?("/builds/")

      src.each_line.with_index(1).flat_map do |line, number|
        families(line).grep(G::SERIF).map { |name| { line: number, message: "serif family #{name}; use the sans" } }
      end
    end

    def families(line)
      line.scan(FAMILY).flatten.flat_map { |value| value.split(",") }.map { |item| item.strip.delete("\"'") }
    end
  end

  GP = GeometryPayload

  














  








  








  







end
