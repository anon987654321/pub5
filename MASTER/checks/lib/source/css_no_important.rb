# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../support/css_autofix_region"
require_relative "../../support/fleet"
require_relative "../../support/brgen_vertical_surfaces"
require_relative "../../../tools/scss"

module Deploy
  # NO_IMPORTANT for the sweep, in the one place the review scans cannot
  # reach: the generated regions.
  #
  # The law itself lives once, in MASTER/law/web.rb#NO_IMPORTANT, with its
  # exemptions - override media, erase-shaped declarations, scan: intentional
  # markers - and laws.yml's catalogue keeps its per-Law policy. Author CSS
  # keeps that budget path: css_constitution tallies !important against
  # css_budget.yml and the ceiling ratchets down; this leaf does not restate
  # either number.
  #
  # What has no budget anywhere is generated CSS. An autofix writer that
  # emitted !important would end the specificity war by nuking it - layer
  # order reverses for important declarations, so one flagged rule in the
  # autofix layer would beat every later layer forever. That is why a hit
  # inside a generated region (either writer's markers, or any @layer autofix
  # block) is a hard failure here, while author hits stay a counted warning
  # pointing at the budget that owns them.
  class CssNoImportantCheck
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    APPS = Fleet.asset_roots.freeze
    MASTER_WEB = %w[MASTER/web/public/face.css MASTER/web/public/chat_upload.css].freeze

    IMPORTANT = /!\s*important/

    def self.run = new.run

    def run
      result = CheckResult.new
      files = css_files
      return result.inconclusive!("css_no_important: no stylesheets found") if files.empty?

      author_hits = 0
      files.each do |path|
        source = File.read(path)
        rel = relative(path)
        regions = CssAutofixRegion.region_bodies(source)

        regions.each_with_index do |body, index|
          next unless body.match?(IMPORTANT)

          where = CssAutofixRegion.wrapped?(body) ? "@layer autofix region" : "generated region ##{index + 1}"
          line = region_line(source, body)
          result.fail("css_no_important: #{rel}:#{line} generated autofix region (#{where}) holds !important - " \
                      "layer order reverses for important declarations; fix the originating rule instead")
        end

        author_hits += unlayered_important_hits(source, regions)

        # An @layer autofix block outside the markers - hand-written, or a
        # region whose markers were deleted but the layer left standing - is
        # under the same ban. The rule's full range is read, not its body:
        # a parent's body holds only its own declarations, and the flag
        # hides inside a nested rule.
        Operator::ScssRules.rules(source).each do |rule|
          next unless rule.parents.empty? && rule.selector.match?(/\A@layer\s+autofix\b/)
          next unless source[rule.range].match?(IMPORTANT)

          result.fail("css_no_important: #{rel}:#{rule.line} @layer autofix block holds !important - " \
                      "layer order reverses for important declarations; fix the originating rule instead")
        end
      end

      if author_hits.positive?
        result.warn("css_no_important: #{author_hits} author !important in author CSS - " \
                    "ceiling and ratchet are owned by css_constitution / css_budget.yml")
      end
      result.checked!(files.size)
      result
    end

    private

    # The source line where the region begins, for the failure message.
    def region_line(source, body)
      probe = body.lines.first.to_s.strip
      index = source.index(probe.to_s) || 0
      source[0...index].count("\n") + 1
    end

    # Author hits: every !important outside the generated regions. The
    # sophisticated shape tests - override media, erase-shaped declarations,
    # scan: intentional markers - belong to law/web.rb and are not restated;
    # this count only feeds the warning that names the budget owner.
    def unlayered_important_hits(source, regions)
      remainder = source.dup
      regions.each { |body| remainder = remainder.sub(body, "") }
      remainder.scan(IMPORTANT).size
    end

    def css_files
      rails = APPS.flat_map do |app|
        bases = [File.join(RAILS, app, "app/assets/stylesheets")]
        bases.concat(EngineRoots.glob(RAILS, app, "app/assets/stylesheets"))
        bases.flat_map do |base|
          next [] unless File.directory?(base)

          Dir.glob(File.join(base, "**/*.{scss,css}")).reject do |p|
            p.include?("/vendor/") || p.include?("/node_modules/") || p.include?("/builds/") ||
              p.match?(/\.map\z/)
          end
        end
      end

      (rails + master_web_files).uniq
    end

    def master_web_files
      MASTER_WEB.map { |rel| File.join(ROOT, rel) }.select { |p| File.file?(p) }
    end

    def relative(path)
      path.sub("#{ROOT}/", "")
    end
  end
end
