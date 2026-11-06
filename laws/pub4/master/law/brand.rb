# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/brand.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8f3a7858149dde8a
require_relative "../lib/master"

# law/brand.rb — the Bergen brand-system laws, one Law.define per law.
#
# Source of every law here is a MEASURED failure or a MEASURED decision from
# building the Sommerseth Eiendom and Alfa Bergen sites (RAILS/__other),
# calibrated against bob.no's production design system. The doctrine lives in
# docs/visual/bergen_brand_systems.md; these laws are the line-level teeth
# /fix walks when it repairs that tree.
#
# 2026-10-28: both source sites were retired and RAILS/__other deleted. The
# laws stay — they are design decisions, and decisions outlive their first
# tree. SIGNAL_COLOR_NAMING, PAPER_NOT_PURE_WHITE and PARAMETRIC_MARK_ONLY are
# scoped (their `path`) to brand-export trees, because the four
# RAILS apps declare --accent, #ffffff and long icon paths as their own
# measured, operator-owned identity (see RAILS/__shared dialect tokens) and
# these three laws must not read that scheme as drift. The remaining three
# walk RAILS/** universally: measured there, zero findings.
























































# DIALECT_CONTRAST_PARITY reads tokens.yml alone: each dialect's light and dark modes keep the
# same contrast per colour role. The values stay operator-owned; the Law reports drift and the
# operator floors of 2026-11-06 (muted 4.5:1, body text 7:1).
require "yaml"
require_relative "../checks/support/rendered_design"

module Law
  module DialectContrast
    ROLES = { "text" => %w[text], "muted" => %w[muted text_secondary], "border" => %w[border],
              "accent" => %w[accent] }.freeze
    NAMES = ROLES.keys.freeze
    FLOOR = { "text" => 7.0, "muted" => 4.5 }.freeze
    DRIFT = %w[muted border].freeze
    TWINS = [%w[brgen_old_light brgen_old_dark], %w[light social]].freeze

    # One dialect's two modes, each a block of colours and the prefix its keys carry.
    Mode = Data.define(:block, :prefix) do
      def ratios = NAMES.to_h { |role| [role, ratio(role)] }

      def ratio(role)
        ground = DialectContrast.rgb(block["#{prefix}bg"]) or return
        ink = ROLES.fetch(role).filter_map { |name| DialectContrast.rgb(block["#{prefix}#{name}"]) }.first or return
        Deploy::RenderedDesign.contrast(ink, ground)
      end
    end

    module_function

    def rgb(hex) = hex.to_s[/\A#(\h{6})\z/, 1]&.then { |digits| digits.scan(/../).map(&:hex) + [1] }

    def both_modes?(block) = block.is_a?(Hash) && block.key?("light_bg") && block.key?("dark_bg")

    # [name, light ratios, dark ratios] for every dialect that has both modes.
    def pairs(tokens)
      inline = tokens.select { |_name, block| both_modes?(block) }.map do |name, block|
        [name, Mode.new(block, "light_").ratios, Mode.new(block, "dark_").ratios]
      end
      inline + twins(tokens)
    end

    def twins(tokens)
      TWINS.filter_map do |light, dark|
        next unless tokens[light].is_a?(Hash) && tokens[dark].is_a?(Hash)

        ["#{light}/#{dark}", Mode.new(tokens[light], "").ratios, Mode.new(tokens[dark], "").ratios]
      end
    end

    def floors(name, modes)
      FLOOR.flat_map do |role, floor|
        modes.filter_map do |mode, ratios|
          value = ratios[role]
          "#{name} #{mode} #{role} is #{value}:1, under #{floor}:1" if value && value < floor
        end
      end
    end

    def drifts(name, modes)
      DRIFT.filter_map do |role|
        light, dark = modes.values.map { |ratios| ratios[role] }
        apart = light && dark && (light - dark).abs > [light, dark].max * 0.35
        "#{name} #{role} is #{light}:1 light and #{dark}:1 dark, more than 35% apart" if apart
      end
    end

    def findings(src)
      tokens = YAML.safe_load(src, aliases: true)&.fetch("tokens", nil)
      return [] unless tokens.is_a?(Hash)

      pairs(tokens).flat_map do |name, light, dark|
        modes = { "light" => light, "dark" => dark }
        (floors(name, modes) + drifts(name, modes)).map { |message| [name.split("/").first, message] }
      end
    rescue Psych::Exception # scan: intentional - a tokens file that does not parse is YAML_SYNTAX's finding
      []
    end

    def fixture(border)
      { "tokens" => { "luxury" => { "light_bg" => "#efefef", "light_text" => "#333333", "light_muted" => "#4d4d4d",
                                    "light_border" => "#888888", "dark_bg" => "#000000", "dark_text" => "#efefef",
                                    "dark_muted" => "#999999", "dark_border" => border } } }.to_yaml
    end
  end

  













end
