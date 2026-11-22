#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic vector logo generation: pure-Ruby SVG path assembly, no
# browser. artwork.rb answers raster; this answers vector. Motifs are
# geometric compositions of capsule strokes; variants compose a motif with
# text, badges or refinement. Every variant is a fixed function of its seed,
# so the same render is byte-identical and a shipped logo can be regenerated
# from its generator instead of being hand-edited in place.

require "digest"
require "fileutils"
require "optparse"
require "stringio"

module Master
  module Tools
    # Geometric SVG logo generator. One motif draws in a 512x512 viewBox;
    # variants wrap it with text, a badge ring or a lighter line weight.
    module Logo
      INK = "#211C15"
      ACCENT = "#7A3B2E"
      PAPER = "#F7F2E9"

      MOTIFS = %w[fetat_hands].freeze
      VARIANTS = %w[pure_symbol text_lockup dash_text circular_badge minimal_refined].freeze

      module_function

      def render(motif:, variant:, subject: "FETAT", seed: nil)
        seed ||= Digest::SHA256.hexdigest("#{motif}/#{variant}/#{subject}")[0, 12]
        generator = motify(motif, seed)
        body = variant_body(generator, variant, subject, seed)
        svg(<<~BODY.chomp, variant, subject)
          #{body}
        BODY
      end

      def write(motif:, variant:, subject:, path:, seed: nil)
        FileUtils.mkdir_p(File.dirname(File.expand_path(path)))
        File.write(path, render(motif:, variant:, subject:, seed:))
        path
      end

      def svg(body, variant = "pure_symbol", _subject = "FETAT")
        <<~SVG
          <?xml version="1.0" encoding="UTF-8"?>
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="#{variant}">
            #{body.strip}
          </svg>
        SVG
      end

      # --- variant composition -------------------------------------------------

      def variant_body(generator, variant, subject, _seed)
        case variant
        when "pure_symbol"
          generator.call
        when "text_lockup"
          <<~BODY
            #{generator.call(offset: 40)}
            #{wordmark(subject, y: 96)}
          BODY
        when "dash_text"
          <<~BODY
            #{generator.call(offset: 40)}
            #{wordmark(subject_with_dash(subject), y: 96)}
          BODY
        when "circular_badge"
          <<~BODY
            <circle cx="256" cy="256" r="238" fill="none" stroke="#{INK}" stroke-width="14"/>
            <g transform="translate(133 24) scale(0.74)">
              #{generator.call}
            </g>
            #{wordmark(subject, y: 430)}
          BODY
        when "minimal_refined"
          refine(generator.call, weight: 10)
        else
          raise ArgumentError, "unknown variant: #{variant}"
        end
      end

      def subject_with_dash(subject)
        return subject if subject.include?("-")

        head, tail = subject[0], subject[1..]
        "#{head}-#{tail}"
      end

      def wordmark(text, y:, x: 256, size: 72, color: INK)
        weight = size * 0.02
        spacing = size * 0.16
        <<~BODY
          <text x="#{x}" y="#{y}" font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
                font-weight="800" font-size="#{size}" fill="#{color}"
                text-anchor="middle" letter-spacing="#{spacing}">#{text}</text>
          <line x1="#{x - 96}" y1="#{y + 26}" x2="#{x + 96}" y2="#{y + 26}" stroke="#{ACCENT}" stroke-width="#{weight.clamp(3.0, 8.0)}"/>
        BODY
      end

      # Refinement re-renders the same geometry at a quieter voice: the
      # generator's bold default (26) is narrowed and colour is collapsed to
      # ink only, so the mark keeps its shape as a line drawing.
      def refine(body, weight: 10)
        body.gsub("stroke-width=\"26\"", "stroke-width=\"#{weight}\"")
      end

      # --- the fetat_hands motif ------------------------------------------------

      # Two open palms rising from opposite lower corners, cupped toward the
      # centre with fingers fanning inward. A capsule stroke draws every digit:
      # round line caps at one bold width — the mark carries a single line
      # width throughout, no shadow layer, no second weight. Each finger is
      # a straight segment with a slight lean, so the whole mark stays
      # symmetric under the x mirror. Strokes are stored as coordinate data and
      # mirrored numerically — never by regex over emitted path text.
      def motify(_motif, seed)
        jitter = jitter_from(seed)
        ->(offset: 0) { hands(offset + jitter) }
      end

      def jitter_from(seed)
        return 0.0 if seed.to_s.empty?

        (seed.to_s.sum % 7) - 3.0
      end

      HAND_STROKES = [
        # The palm hook: wrist at the bottom, up the outside, curling inward.
        [:curve, [452 + 0, 462], [[486, 402], [484, 330], [442, 294]]],
        # The fingers, fanned upward-inward from the palm tip.
        [:segment, [404, 248], [376, 168]],
        [:segment, [432, 240], [414, 148]],
        [:segment, [460, 254], [458, 166]],
        [:segment, [482, 288], [492, 214]],
        # The palm shelf the fingers rise from, and the thumb fold.
        [:segment, [442, 294], [374, 286]],
        [:segment, [442, 294], [474, 338]],
      ].freeze

      def hands(offset = 0)
        right = path_d(HAND_STROKES, offset)
        left = path_d(HAND_STROKES.map { mirror_stroke(_1, offset) }, 0)
        <<~BODY
          <g fill="none" stroke="#{INK}" stroke-width="#{STROKE_WIDTH}" stroke-linecap="round" stroke-linejoin="round">
            #{right}
            #{left}
          </g>
        BODY
      end

      # Every stroke the motif draws, in one breadth. Variants may narrow the
      # whole mark, but nothing inside it may differ from the rest.
      STROKE_WIDTH = 26

      def path_d(strokes, offset)
        strokes.map do |(kind, anchor, tail)|
          case kind
          when :segment
            anchor = [anchor[0] + offset, anchor[1]]
            tail = [tail[0] + offset, tail[1]]
            %(<path d="M #{anchor.join(" ")} L #{tail.join(" ")}"/>)
          when :curve
            %(<path d="M #{anchor.join(" ")} C #{tail.map { |xy| xy.join(" ") }.join(" ")}"/>)
          end
        end.join("\n")
      end

      # The left hand is the right hand mirrored through the vertical axis of
      # the viewBox, so symmetry is a property of the generator, not a second
      # path to keep in step.
      def mirror_stroke((kind, anchor, tail), _offset)
        flip = ->(xy) { [(512 - xy[0]), xy[1]] }
        mirrored_tail = case kind
                        when :segment then flip.call(tail)
                        when :curve then tail.map(&flip)
                        end
        [kind, flip.call(anchor), mirrored_tail]
      end
    end
  end
end

class LogoCLI
  def self.run!(argv)
    options = { motif: "fetat_hands", variants: Master::Tools::Logo::VARIANTS, subject: "FETAT", out: nil, seed: nil }
    OptionParser.new do |opts|
      opts.banner = "usage: logo.rb --out DIR [options]"
      opts.on("--out DIR") { |v| options[:out] = v }
      opts.on("--motif NAME") { |v| options[:motif] = v }
      opts.on("--subject TEXT") { |v| options[:subject] = v }
      opts.on("--variants a,b,c") { |v| options[:variants] = v.split(",") }
      opts.on("--seed SEED") { |v| options[:seed] = v }
    end.parse!(argv)

    out = options[:out] || "logos"
    names = {
      "pure_symbol" => "01-pure-symbol.svg",
      "text_lockup" => "02-#{options[:subject].downcase}-text.svg",
      "dash_text" => "03-#{options[:subject].downcase}-dash-text.svg",
      "circular_badge" => "04-circular-badge.svg",
      "minimal_refined" => "05-minimal-refined.svg",
    }

    options[:variants].each do |variant|
      raise ArgumentError, "unknown variant #{variant}" unless Master::Tools::Logo::VARIANTS.include?(variant)

      path = File.join(out, names.fetch(variant))
      Master::Tools::Logo.write(motif: options[:motif], variant:, subject: options[:subject], path:, seed: options[:seed])
      puts path
    end
  end
end

if $PROGRAM_NAME == __FILE__
  LogoCLI.run!(ARGV)
end
