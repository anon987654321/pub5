# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../support/brgen_vertical_surfaces"
require_relative "../../support/fleet"
require_relative "../../../lib/io/exec"
require_relative "../../../tools/scss"
require "base64"
require "json"
require "rbconfig"
require "set"

module Deploy
  # dart-sass's compressed output mode has a real, reproducible bug: a long
  # comma-separated compound-selector list can lose an individual selector's
  # qualifying class during minification (confirmed live on brgen.no --
  # every post avatar rendered as a full-width bar instead of a small circle
  # because ".feed-card.listing .feed-card-avatar, ..." compressed down to a
  # bare ".feed-card-avatar" that then matched every card, not just listings).
  # This check compiles each app's stylesheet entrypoint in both :expanded and
  # :compressed mode and fails if any selector present in the expanded output
  # is missing from the compressed output -- catching that bug class before
  # it ships, regardless of which SCSS file introduces it next.
  #
  # The selector-loss half cannot fire on the pinned dart-sass (1.101.0): long
  # compound lists, quoted attributes, escaped and unicode selectors, :is(),
  # @media and @supports all survive compression intact. What this check proves
  # today is that each entrypoint compiles. Re-check the loss half whenever
  # sass-embedded moves in a Gemfile.lock.
  class CssMinifyIntegrityCheck
    ROOT = File.expand_path("../../../..", __dir__)

    RAILS_ROOT = File.join(ROOT, "RAILS")
    # master has no application.scss to compile; its face CSS is hand-written.
    APPS = Fleet.engine_apps.freeze
    MIN_SELECTOR_LIST_SIZE = 3
    COMPILE_TIMEOUT = 900
    SASS_COMPILER = <<~'RUBY'.freeze
      require "base64"
      require "json"
      require "sass-embedded"

      begin
        entry = ARGV.fetch(0)
        load_paths = JSON.parse(ARGV.fetch(1))
        expanded = Sass.compile(entry, load_paths:, style: :expanded).css
        compressed = Sass.compile(entry, load_paths:, style: :compressed).css
        result = JSON.generate("expanded" => expanded, "compressed" => compressed)
        STDOUT.puts("CSS_MINIFY_RESULT:#{Base64.strict_encode64(result)}")
      rescue StandardError => error
        warn "#{error.class}: #{error.message}"
        exit 1
      end
    RUBY

    def self.run
      new.run
    end

    def run
      result = CheckResult.new

      begin
        require "sass-embedded"
      rescue LoadError
        result.inconclusive!("css_minify_integrity: sass-embedded gem unavailable - no stylesheet compiled")
        return result
      end

      APPS.each { |app| check_app(result, app) }
      result
    end

    private

    def check_app(result, app, compiler: nil)
      compiler ||= method(:compile_stylesheets)
      entry = File.join(RAILS_ROOT, app, "app/assets/stylesheets/application.scss")
      return result.inconclusive!("css_minify_integrity: #{app} has no application.scss") unless File.file?(entry)

      # The engine paths are not optional. Rails puts each mounted engine's
      # app/assets on the asset load path, so `rake dartsass:build` compiles;
      # this list is hand-built, and without them brgen's application.scss cannot
      # resolve its vertical imports. The check did not report "brgen unchecked",
      # it reported a Sass::CompileError — so a path list that had gone stale
      # read as a broken stylesheet, and the minify check it exists to run never
      # executed for brgen at all.
      load_paths = [
        File.join(RAILS_ROOT, "__shared", "app/assets/stylesheets"),
        File.join(RAILS_ROOT, app, "app/assets/stylesheets"),
        *EngineRoots.glob(RAILS_ROOT, app, "app/assets/stylesheets"),
      ]

      begin
        compiled = compiler.call(entry:, load_paths:)
        expanded = compiled.fetch("expanded")
        compressed = compiled.fetch("compressed")
      rescue StandardError => e
        result.fail("css_minify_integrity: #{app} failed to compile (#{e.class}: #{e.message})")
        return
      end

      # Build one exact selector index for the compressed output. This avoids
      # rescanning the full stylesheet for every selector and prevents a longer
      # selector from satisfying a missing shorter selector by substring match.
      compressed_selectors = selector_set(compressed)
      Operator::ScssRules.rules(expanded).each do |rule|
        next if rule.at_rule?

        selectors = rule.selectors
        next if selectors.length < MIN_SELECTOR_LIST_SIZE

        missing = selectors.reject { |sel| compressed_selectors.include?(normalize_selector(sel)) }
        next if missing.empty?

        result.fail(
          "css_minify_integrity: #{app} lost selector(s) under compression -- " \
          "list started with #{selectors.first.inspect} (#{selectors.length} items), " \
          "missing after compression: #{missing.inspect}",
        )
      end

      # This app's stylesheet was compiled and compared; an app without an
      # application.scss should not make the ones that have it count for nothing.
      result.checked!
    end

    # Compile Sass in a separately supervised process. The embedded compiler
    # owns a Dart process of its own; keeping it inside this check's Ruby process
    # meant the runner's script timeout could not interrupt or reap a wedged compile.
    def compile_stylesheets(entry:, load_paths:)
      output, status = Master::Io::Exec.capture2e(
        ENV.to_h, RbConfig.ruby, "-e", SASS_COMPILER, entry, JSON.generate(load_paths),
        chdir: ROOT, timeout: COMPILE_TIMEOUT, raise_on_timeout: true
      )
      unless status.success?
        detail = output.to_s.lines.last(4).join.strip
        raise "Sass compiler subprocess exited #{status.exitstatus || "signal"}: #{detail}"
      end

      record = output.to_s.lines.reverse.find { |line| line.start_with?("CSS_MINIFY_RESULT:") }
      raise "Sass compiler subprocess produced no result: #{output.to_s.lines.last(4).join.strip}" unless record

      payload = record.delete_prefix("CSS_MINIFY_RESULT:").strip
      JSON.parse(Base64.strict_decode64(payload))
    rescue Master::Io::Exec::TimeoutError
      raise "Sass compilation timed out after #{COMPILE_TIMEOUT}s"
    end

    # Exact normalized selectors from the compressed stylesheet. The shared
    # parser keeps commas inside :is(), attributes and quoted strings intact.
    def selector_set(css)
      Operator::ScssRules.rules(css).each_with_object(Set.new) do |rule, selectors|
        next if rule.at_rule?

        rule.selectors.each { |selector| selectors << normalize_selector(selector) }
      end
    end

    # dart-sass's compressed output strips whitespace immediately around
    # explicit combinators (>, +, ~) but keeps the single space that IS the
    # descendant combinator between simple selectors (e.g. ".a>b c", not
    # ".a>bc"). Normalize both sides the same way instead of stripping all
    # whitespace, which produced false positives on exactly these selectors.
    def normalize_selector(text)
      chars = text.chars
      normalized = +""
      quote = nil
      escaped = false
      last_was_combinator = false
      combinators = %w[> + ~]
      index = 0

      while index < chars.length
        character = chars[index]

        if quote
          normalized << character
          if escaped
            escaped = false
          elsif character == "\\"
            escaped = true
          elsif character == quote
            quote = nil
          end
          index += 1
          next
        end

        if escaped
          normalized << character
          escaped = false
          last_was_combinator = false
          index += 1
          next
        end

        if character == "\\"
          normalized << character
          escaped = true
          last_was_combinator = false
          index += 1
          next
        end

        if character == '"' || character == "'"
          normalized << character
          quote = character
          last_was_combinator = false
          index += 1
          next
        end

        if character.match?(/\s/)
          index += 1 while index < chars.length && chars[index].match?(/\s/)
          following = chars[index]
          if !normalized.empty? && normalized[-1] != " " &&
             !last_was_combinator && !combinators.include?(following)
            normalized << " "
          end
          next
        end

        if combinators.include?(character)
          normalized.rstrip!
          normalized << character
          last_was_combinator = true
        else
          normalized << character
          last_was_combinator = false
        end
        index += 1
      end

      normalized.strip
    end
  end
end
