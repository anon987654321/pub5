# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../support/css_autofix_region"
require_relative "../../support/fleet"
require_relative "../../support/brgen_vertical_surfaces"
require_relative "../../../tools/scss"
require "yaml"

module Deploy
  # The one cascade architecture, read at the source.
  #
  # data/css_architecture.yml owns the layer order. Every Rails app entry
  # (application.scss) either declares it exactly once - and then keeps its
  # author rules inside named layers and its generated autofix region inside
  # @layer autofix - or carries no stack at all yet, which is migration debt
  # and lands as a warning, not a pass shaped like one. Partials never
  # declare an order statement: a second `@layer a, b, c;` anywhere is a
  # competing architecture, the exact drift SINGULARITY forbids.
  #
  # The precedence trap this check exists to catch: unlayered normal rules
  # beat every layered rule. An entry that declares the stack while its
  # author CSS stays unlayered demotes a wrapped autofix region below the
  # rules the region exists to fix, so that shape is a failure, not a warn.
  class CssLayerStackCheck
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    DATA = File.join(ROOT, "MASTER", "data", "css_architecture.yml")
    APPS = Fleet.asset_roots.freeze

    # Sass constructs that open a depth-0 block without being a rule. Their
    # contents compile into the surrounding layer; the block itself is
    # authoring, not cascade placement.
    NON_RULE_PRELUDE = /\A@(?:mixin|function|if|each|for|while)\b/

    def self.run = new.run

    def run
      @result = CheckResult.new
      @architecture = architecture
      return @result if @architecture.nil?

      entries = []
      partials = []
      APPS.each do |app|
        stylesheet_roots(app).each do |base|
          next unless File.directory?(base)

          Dir.glob(File.join(base, "**/*.scss")).reject { |p| p.match?(/\/vendor\/|\/node_modules\/|\/builds\//) }
             .each do |path|
            File.basename(path) == "application.scss" ? entries << path : partials << path
          end
        end
      end

      if entries.empty? && partials.empty?
        return @result.inconclusive!("css_layer_stack: no stylesheets found")
      end

      entries.each { |path| check_entry(path) }
      partials.each { |path| check_partial(path) }
      @result.checked!(entries.size + partials.size)
      @result
    end

    private

    def architecture
      data = YAML.safe_load_file(DATA)
      order = data&.dig("cascade_layers", "order")
      raise "cascade_layers.order missing" unless order.is_a?(Array) && order.size >= 2

      order
    rescue StandardError => e
      @result.inconclusive!("css_layer_stack: css_architecture.yml unreadable (#{e.class}: #{e.message})")
      nil
    end

    def stylesheet_roots(app)
      bases = [File.join(RAILS, app, "app/assets/stylesheets")]
      bases.concat(EngineRoots.glob(RAILS, app, "app/assets/stylesheets"))
      bases
    end

    def check_entry(path)
      rel = relative(path)
      source = File.read(path)
      statements = source.lines.grep(CssAutofixRegion::ORDER_STATEMENT)

      if statements.empty?
        @result.warn("css_layer_stack: #{rel} declares no cascade layer stack - migration debt " \
                    "(order: #{@architecture.join(', ')})")
        return
      end

      if statements.size > 1
        @result.fail("css_layer_stack: #{rel} declares #{statements.size} @layer order statements - " \
                     "one entry owns the stack; delete the competitors")
        return
      end

      names = statements.first.strip.sub(/\A@layer\s+/, "").sub(/;\s*\z/, "").split(",").map(&:strip)
      if names != @architecture
        @result.fail("css_layer_stack: #{rel} order #{names.join(', ')} does not match " \
                     "MASTER/data/css_architecture.yml (#{@architecture.join(', ')})")
        return
      end

      check_generated_region(rel, source)
      check_unlayered_rules(rel, source)
    end

    # A stack-declared entry must carry its generated autofix region inside
    # @layer autofix, and must have no author rule left outside a layer.
    def check_generated_region(rel, source)
      CssAutofixRegion.region_bodies(source).each do |body|
        next if CssAutofixRegion.wrapped?(body)

        @result.fail("css_layer_stack: #{rel} carries a generated autofix region outside " \
                     "@layer autofix while declaring the stack - unlayered author rules would beat it")
      end
    end

    def check_unlayered_rules(rel, source)
      unlayered = unlayered_top_level_blocks(source)
      return if unlayered.zero?

      @result.fail("css_layer_stack: #{rel} declares the stack but holds #{unlayered} top-level " \
                   "block(s) outside any @layer - unlayered rules beat every layered rule, so " \
                   "wrap the author CSS in its layer or hold the stack until it is")
    end

    # Depth-0 blocks whose prelude is not @layer and not a Sass authoring
    # construct. rules() already resolves nesting, so a top-level block is
    # exactly a rule with no parents - the same lexer css_brace_balance trusts
    # for brace truth.
    def unlayered_top_level_blocks(source)
      Operator::ScssRules.rules(source).count do |rule|
        rule.parents.empty? && rule.selector !~ /\A@layer\b/ && rule.selector !~ NON_RULE_PRELUDE
      end
    end

    def check_partial(path)
      source = File.read(path)
      return unless source.match?(CssAutofixRegion::ORDER_STATEMENT)

      @result.fail("css_layer_stack: #{relative(path)} declares a @layer order statement - " \
                   "partials contribute rules via mixin or meta.load-css; the entry owns the stack")
    end

    def relative(path)
      path.sub("#{ROOT}/", "")
    end
  end
end
