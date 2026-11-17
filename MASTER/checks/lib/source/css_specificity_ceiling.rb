# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../support/fleet"
require "yaml"

module Deploy
  # CSS_SPECIFICITY_CEILING against the compiled stylesheets.
  #
  # Layers decide precedence now; a selector past the ceiling is a specificity
  # war this architecture exists to end. The measurement is post-compile by
  # design: Sass nesting expands before the browser sees it, so source depth
  # under-measures what actually ships. Each app's build output
  # (app/assets/builds/application.css) is read when it exists; an app with no
  # build is an honest INCONCLUSIVE, not a pass.
  #
  # Severity follows data/css_architecture.yml#specificity.mode - warn while
  # baselines are being recorded, fail once an app's baseline is ratcheted.
  # The default mode is warn.
  class CssSpecificityCeilingCheck
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    DATA = File.join(ROOT, "MASTER", "data", "css_architecture.yml")
    APPS = Fleet.asset_roots.freeze

    DIAGNOSTIC_LIMIT = 10

    def self.run = new.run

    def run
      result = CheckResult.new
      config = architecture
      return config if config.is_a?(CheckResult)

      ceiling = parse_ceiling(config[:ceiling])
      mode = config[:mode]
      checked = 0

      APPS.each do |app|
        built = File.join(RAILS, app, "app/assets/builds/application.css")
        unless File.file?(built)
          result.inconclusive!("css_specificity_ceiling: #{app} has no compiled build (#{relative(built)}) - " \
                               "run MASTER/tools/rails/build_all_css.rb to measure it")
          next
        end

        checked += 1
        offenders = specificity_offenders(File.read(built), ceiling)
        next if offenders.empty?

        offenders.first(DIAGNOSTIC_LIMIT).each do |selector, tuple|
          message = "css_specificity_ceiling: #{app} #{tuple} exceeds #{config[:ceiling]} - #{selector}"
          mode == "fail" ? result.fail(message) : result.warn(message)
        end
        result.warn("css_specificity_ceiling: #{app} #{offenders.size - DIAGNOSTIC_LIMIT} additional " \
                    "offender(s) omitted") if offenders.size > DIAGNOSTIC_LIMIT
        summary = "#{app}: #{offenders.size} selector(s) above #{config[:ceiling]} (mode #{mode})"
        mode == "fail" ? result.fail("css_specificity_ceiling: #{summary}") : result.warn(summary)
      end

      result.checked!(checked)
      result
    end

    private

    def architecture
      data = YAML.safe_load_file(DATA)
      spec = data&.dig("specificity")
      raise "specificity block missing" unless spec.is_a?(Hash)

      { ceiling: spec.fetch("ceiling"), mode: spec.fetch("mode", "warn") }
    rescue StandardError => e
      error = CheckResult.new
      error.inconclusive!("css_specificity_ceiling: css_architecture.yml unreadable (#{e.class}: #{e.message})")
      error
    end

    def parse_ceiling(text)
      a, b, c = text.to_s.split(",").map { |part| part.to_s.strip.to_i }
      [a || 0, b || 0, c || 0]
    end

    # Selectors above the ceiling, ordered worst first. [id, class, type] tuples.
    def specificity_offenders(css, ceiling)
      compiled_selectors(css).filter_map { |selector| [selector, specificity(selector)] }
                            .select { |_, tuple| above?(tuple, ceiling) }
                            .sort_by { |_, (a, b, c)| [-(a * 100 + b * 10 + c)] }
                            .map { |selector, tuple| [selector, tuple.join(",")] }
                            .uniq
    end

    def above?(tuple, ceiling)
      a, b, c = tuple
      ca, cb, cc = ceiling
      a > ca || (a == ca && (b > cb || (b == cb && c > cc)))
    end

    # Selectors from compiled CSS: everything before a `{` that is not a
    # declaration line inside a block. Comment text is dropped first.
    def compiled_selectors(css)
      css = css.gsub(%r{/\*.*?\*/}m, "")
      css.split(/[{}]/).each_with_index.filter_map do |chunk, index|
        next if index.odd? # inside a block: declarations, not selectors

        chunk.strip.split("\n").last.to_s.strip
      end.select { |selector| selector.match?(/[#.:\w]/) && !selector.start_with?("@", "%") }
         .flat_map { |selector| Operator::ScssRules.split_list(selector) }
         .reject { |selector| selector.match?(/\A(?:from|to|\d+%)\z/) }
    end

    # [id, class-and-attribute-and-pseudo-class, type-and-pseudo-element].
    # :where() contributes zero and is removed. :is()/:not() keep their
    # arguments' counts (spec: the most specific argument; counting all is the
    # conservative over-approximation, which is the safe direction for a
    # ceiling).
    def specificity(selector)
      spec = selector.gsub(/:where\([^()]*\)/i, "")
      ids = spec.scan(/#[A-Za-z0-9_-]+/).size
      classes = spec.scan(/\.[A-Za-z0-9_-]+|\[[^\]]*\]|(?<!:):(?!:)[A-Za-z-]+(?:\([^()]*\))?/).size
      types = spec.scan(/(?:\A|[\s>+~])[A-Za-z][A-Za-z0-9]*(?=[\s>+~:{\[]|\z)|::[A-Za-z-]+/).size
      [ids, classes, types]
    end

    def relative(path)
      path.sub("#{ROOT}/", "")
    end
  end
end
