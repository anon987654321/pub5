# frozen_string_literal: true

# plur1bus plates — ten radically different renderings of the canonical amber
# mark. Every plate extracts the Caprasimo glyph outlines and the nine white
# swoosh hairlines straight from the live logo partial, so the wordmark and
# the swoosh geometry stay identical to the shipped mark (same font, same
# swoosh style and lines); only the material, ground and grade around them
# change. Every random layer is seeded, so a rerun reproduces the plates.
#
# Usage: ruby generate.rb
# Writes plates/*.svg and all-plates.html (all ten on one page).

require "fileutils"

PLATES_DIR = __dir__
OUT_DIR    = File.join(PLATES_DIR, "plates")
ROOT       = File.expand_path("../../../..", __dir__)
PARTIAL    = File.join(ROOT, "RAILS/amber/app/views/shared/_logo.html.erb")

ERB_SRC    = File.read(PARTIAL)
GLYPHS     = ERB_SRC.scan(/caprasimo-([a-z]+)" d="([^"]+)"/).to_h
TRANSFORMS = ERB_SRC.scan(/caprasimo-([a-z]+)" transform="([^"]+)"/).to_h
HAIRLINES  = ERB_SRC.scan(%r{<path stroke="#FFFFFF" stroke-width="([\d.]+)"[^>]*d="([^"]+)"}).map { |w, d| [w.to_f, d] }
CARRIER    = "M50,220 C250,180 750,180 950,220" # the original textPath carrier curve

raise "glyph extraction failed (#{GLYPHS.size})" unless GLYPHS.size == 6 && TRANSFORMS.size == 6
raise "hairline extraction failed (#{HAIRLINES.size})" unless HAIRLINES.size == 9

RADIAL = [500.0, 250.0, 560.0] # frozen position of the animated radial ink
PASTEL = ["#ffb999", "#e6cce6", "#cce6cc", "#99e6e6"].freeze

PLATES = []

def radial_t(x, y)
  d = Math.sqrt((x - RADIAL[0])**2 + (y - RADIAL[1])**2) / RADIAL[2]
  d > 1.0 ? 1.0 : d
end

def defs_glyphs(p)
  GLYPHS.map { |g, d| %(<path id="#{p}-caprasimo-#{g}" d="#{d}"/>) }.join
end

def mask(p)
  uses = GLYPHS.keys.map { |g| %(<use href="##{p}-caprasimo-#{g}" transform="#{TRANSFORMS[g]}"/>) }.join
  %(<clipPath id="#{p}-text-mask">#{uses}</clipPath>)
end

def svg_doc(name, title, ground, body, extra_defs = "")
  p = "pl#{name}"
  <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 500" role="img">
      <title>#{title}</title>
      <defs>#{defs_glyphs(p)}#{mask(p)}#{extra_defs}</defs>
      #{ground}
      #{body}
    </svg>
  SVG
end

def ink(p, content)
  %(<g clip-path="url(##{p}-text-mask)">#{content}</g>)
end

def hairlines(color, extra = {})
  ex = extra.map { |k, v| %( #{k}="#{v}") }.join
  HAIRLINES.map { |w, d| %(<path d="#{d}" fill="none" stroke="#{color}" stroke-width="#{w}"#{ex}/>) }.join
end

def sparkle(x, y, s, color, opacity = 1.0)
  %(<path d="M#{x} #{y - s} Q#{x} #{y} #{x + s} #{y} Q#{x} #{y} #{x} #{y + s} Q#{x} #{y} #{x - s} #{y} Q#{x} #{y} #{x} #{y - s} Z" fill="#{color}" opacity="#{opacity}"/>)
end

def plus(x, y, s, color)
  %(<g fill="#{color}"><rect x="#{x - s}" y="#{y - s / 3.0}" width="#{2 * s}" height="#{2 * s / 3.0}"/>\
<rect x="#{x - s / 3.0}" y="#{y - s}" width="#{2 * s / 3.0}" height="#{2 * s}"/></g>)
end

# Base hairline curve (y0 = 180) as anchor/control/end points; every hairline
# in the partial is this curve translated down by (y0 - 180).
BASE_A = [[50, 180], [200, 100], [400, 200], [600, 100]].freeze
BASE_B = [[600, 100], [800, 0], [850, 160], [950, 130]].freeze

def bez_points(q0, q1, q2, q3, n)
  (0..n).map do |i|
    t = i.to_f / n
    u = 1 - t
    x = u**3 * q0[0] + 3 * u**2 * t * q1[0] + 3 * u * t**2 * q2[0] + t**3 * q3[0]
    y = u**3 * q0[1] + 3 * u**2 * t * q1[1] + 3 * u * t**2 * q2[1] + t**3 * q3[1]
    [x, y]
  end
end

def stepped_path(y0, grid)
  pts = bez_points(*BASE_A, 14) + bez_points(*BASE_B, 14)[1..]
  pts.map { |x, y| [x, y + (y0 - 180)] }
     .map { |x, y| [(x / grid).round * grid, (y / grid).round * grid] }
     .map.with_index { |(x, y), i| "#{i.zero? ? 'M' : 'L'}#{x} #{y}" }.join
end

def plate(num, slug, title, ground, body, extra_defs = "")
  name = format("%02d", num)
  File.write(File.join(OUT_DIR, "#{name}_#{slug}.svg"), svg_doc(name, title, ground, body, extra_defs))
  PLATES << { num: name, slug: slug, title: title }
end

# 01 — greyscale particle stipple: many carriers, one readable form.
def p01
  p = "pl01"
  r = Random.new(5701)
  field = Array.new(500) do
    %(<circle cx="#{r.rand(0.0..1000).round(1)}" cy="#{r.rand(0.0..500).round(1)}" r="#{r.rand(0.5..1.0).round(2)}" fill="#ECECEC" opacity="#{r.rand(0.04..0.12).round(2)}"/>)
  end.join
  dense = Array.new(5200).map.with_index do |_, i|
    x = r.rand(40.0..520).round(1)
    y = r.rand(135.0..290).round(1)
    if (i % 97).zero?
      %(<circle cx="#{x}" cy="#{y}" r="#{r.rand(1.6..2.4).round(2)}" fill="#C8F55F"/>)
    else
      %(<circle cx="#{x}" cy="#{y}" r="#{r.rand(1.0..2.2).round(2)}" fill="#ECECEC" opacity="#{r.rand(0.75..1.0).round(2)}"/>)
    end
  end.join
  lines = HAIRLINES.map.with_index do |(w, d), i|
    %(<path d="#{d}" fill="none" stroke="#ECECEC" stroke-width="#{w}" stroke-linecap="round" stroke-dasharray="0.1 7" opacity="#{(0.7 - i * 0.05).round(2)}"/>)
  end.join
  carrier = %(<path d="#{CARRIER}" fill="none" stroke="#C8F55F" stroke-width="1.2" stroke-linecap="round" stroke-dasharray="0.1 9" opacity="0.45"/>)
  body = field + ink(p, dense) + carrier + lines
  plate(1, "stipple_unum", "amber mark — greyscale stipple: many carriers, one readable form",
        %(<rect width="1000" height="500" fill="#0A0A0A"/>), body)
end

# 02 — 8-bit bit-reduction: quantized radial ink, stepped pixel hairlines, CRT scanlines.
def p02
  p = "pl02"
  grid = 12.5
  cells = (0..79).flat_map do |cx|
    (0..23).map do |cy|
      idx = (radial_t(cx * grid + grid / 2, 100 + cy * grid + grid / 2) * 3).round
      %(<rect x="#{cx * grid}" y="#{100 + cy * grid}" width="#{grid}" height="#{grid}" fill="#{PASTEL[idx]}"/>)
    end
  end.join
  lines = HAIRLINES.map do |w, d|
    y0 = d[/M50,(\d+)/, 1].to_i
    %(<path d="#{stepped_path(y0, grid)}" fill="none" stroke="#FFFFFF" stroke-width="#{w}" shape-rendering="crispEdges" opacity="0.92"/>)
  end.join
  sparks = [[70, 90, PASTEL[0]], [250, 70, PASTEL[3]], [560, 85, PASTEL[1]], [820, 100, PASTEL[2]]]
           .map { |x, y, c| plus(x, y, 8, c) }.join
  cursor = %(<rect x="480" y="146" width="12" height="24" fill="#e6cce6"/>)
  scan = (0..99).map { |i| %(<rect x="0" y="#{i * 5}" width="1000" height="2" fill="#000" opacity="0.14"/>) }.join
  body = ink(p, cells) + lines + sparks + cursor + scan
  plate(2, "bit8_pixel", "amber mark — 8-bit bit-reduction, stepped swoosh, CRT scanlines",
        %(<rect width="1000" height="500" fill="#101010"/>), body)
end

# 03 — 4-bit Bayer dither: ordered-dither ink on paper, one-bit hairlines.
def p03
  p = "pl03"
  cell = 10
  bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]].map { |row| row.map { |v| (v + 0.5) / 16.0 } }
  rects = (0..49).flat_map do |cx|
    (0..19).map do |cy|
      x = 35 + cx * cell
      y = 105 + cy * cell
      t = radial_t(x + cell / 2.0, y + cell / 2.0)
      b = bayer[cy % 4][cx % 4]
      fill = if t > b then "#17130E" elsif t > b - 0.42 then "#C88A4A" end
      fill ? %(<rect x="#{x}" y="#{y}" width="#{cell}" height="#{cell}" fill="#{fill}"/>) : ""
    end
  end.join
  carrier = %(<path d="#{CARRIER}" fill="none" stroke="#17130E" stroke-width="1" opacity="0.4"/>)
  body = ink(p, rects) + hairlines("#17130E") + carrier
  plate(3, "dither4_press", "amber mark — 4-bit Bayer dither on paper, one-bit swoosh",
        %(<rect width="1000" height="500" fill="#F2EFE6"/>), body)
end

# 04 — prism: spectral ink, each hairline a different ray of the spectrum.
def p04
  p = "pl04"
  hues = %w[#FF5E5E #FF9D5C #FFE45C #7DFF8A #5CC8FF #6E7DFF #8A5CFF #C85CFF #FF5CE1]
  grad = %(<linearGradient id="pl04-ink" gradientUnits="userSpaceOnUse" x1="40" y1="290" x2="520" y2="160">\
<stop offset="0" stop-color="#FF5E5E"/><stop offset="0.17" stop-color="#FF9D5C"/>\
<stop offset="0.33" stop-color="#FFE45C"/><stop offset="0.5" stop-color="#7DFF8A"/>\
<stop offset="0.67" stop-color="#5CC8FF"/><stop offset="0.83" stop-color="#8A7DFF"/>\
<stop offset="1" stop-color="#FF5CE1"/></linearGradient>)
  body = ink(p, %(<rect width="1000" height="500" fill="url(#pl04-ink)"/>))
  body += HAIRLINES.map.with_index { |(w, d), i| %(<path d="#{d}" fill="none" stroke="#{hues[i]}" stroke-width="#{w}" opacity="0.9"/>) }.join
  body += HAIRLINES.map { |w, d| y0 = d[/M50,(\d+)/, 1].to_i; sparkle(950, y0 - 50, 4 + w, "#FFFFFF", 0.95) }.join
  r = Random.new(5704)
  body += Array.new(60) { %(<circle cx="#{r.rand(0.0..1000).round(1)}" cy="#{r.rand(0.0..500).round(1)}" r="0.9" fill="#FFF" opacity="0.22"/>) }.join
  plate(4, "prism_rainbow", "amber mark — spectral ink, prismatic swoosh rays",
        %(<rect width="1000" height="500" fill="#0E0E16"/>), body, grad)
end

# 05 — comet night: hairlines become comet trails with star heads.
def p05
  p = "pl05"
  grad = %(<linearGradient id="pl05-trail" gradientUnits="userSpaceOnUse" x1="50" y1="0" x2="950" y2="0">\
<stop offset="0" stop-color="#FFFFFF" stop-opacity="0"/><stop offset="0.45" stop-color="#DCE6FF" stop-opacity="0.4"/>\
<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.95"/></linearGradient>)
  inkg = %(<linearGradient id="pl05-ink" gradientUnits="userSpaceOnUse" x1="50" y1="280" x2="520" y2="170">\
<stop offset="0" stop-color="#F2F4FF"/><stop offset="0.55" stop-color="#C9D2F2"/><stop offset="1" stop-color="#98A6D8"/></linearGradient>)
  r = Random.new(5705)
  stars = Array.new(110) { %(<circle cx="#{r.rand(0.0..1000).round(1)}" cy="#{r.rand(0.0..500).round(1)}" r="#{r.rand(0.5..1.4).round(2)}" fill="#FFF" opacity="#{r.rand(0.15..0.85).round(2)}"/>) }.join
  body = stars
  body += ink(p, %(<rect width="1000" height="500" fill="url(#pl05-ink)"/>))
  body += HAIRLINES.map { |w, d| %(<path d="#{d}" fill="none" stroke="url(#pl05-trail)" stroke-width="#{w}"/>) }.join
  body += HAIRLINES.last(3).map { |w, d| y0 = d[/M50,(\d+)/, 1].to_i; sparkle(950, y0 - 50, 5 + w, "#FFFFFF", 0.95) }.join
  body += %(<path d="M60,120 C260,60 460,150 660,70 S880,110 958,78" fill="none" stroke="url(#pl05-trail)" stroke-width="5" opacity="0.9"/>)
  body += sparkle(956, 80, 12, "#FFFFFF", 0.95)
  plate(5, "comet_night", "amber mark — moonlight ink, swoosh comet trails",
        %(<rect width="1000" height="500" fill="#070B14"/>), body, grad + inkg)
end

# 06 — synthwave: sliced sun ink, neon swoosh, perspective grid below the horizon.
def p06
  p = "pl06"
  grad = %(<linearGradient id="pl06-ink" gradientUnits="userSpaceOnUse" x1="0" y1="115" x2="0" y2="290">\
<stop offset="0" stop-color="#FFC24D"/><stop offset="0.55" stop-color="#FF6B5E"/><stop offset="1" stop-color="#C93AFF"/></linearGradient>)
  slices = [[150, 156], [168, 176], [188, 198], [210, 224], [234, 252]]
           .map { |a, b| %(<rect x="0" y="#{a}" width="1000" height="#{b - a}" fill="#14002B"/>) }.join
  glow = HAIRLINES.map { |w, d| %(<path d="#{d}" fill="none" stroke="#FF4FD8" stroke-width="#{w + 1.6}" opacity="0.5" transform="translate(0,3)"/>) }.join
  neon = HAIRLINES.map { |w, d| %(<path d="#{d}" fill="none" stroke="#52F2FF" stroke-width="#{w}"/>) }.join
  horizon = %(<path d="M0 330 H1000" stroke="#52F2FF" stroke-width="1.5" opacity="0.7"/>)
  grid = (0..10).map { |i| x = i * 100; %(<path d="M#{x} 330 L#{x + (x - 500) * 0.4} 500" stroke="#FF4FD8" opacity="0.28"/>) }.join
  grid += [355, 385, 420, 460].map { |y| %(<path d="M0 #{y} H1000" stroke="#52F2FF" opacity="0.18"/>) }.join
  body = ink(p, %(<rect width="1000" height="500" fill="url(#pl06-ink)"/>) + slices) + glow + neon + horizon + grid
  plate(6, "synthwave_sun", "amber mark — sliced sun ink over a neon grid horizon",
        %(<rect width="1000" height="500" fill="#14002B"/>), body, grad)
end

# 07 — zoetrope: onion-skin ghosts of the wordmark riding the carrier curve.
def p07
  p = "pl07"
  ghosts = [[-105, 24, 0.12], [-70, 16, 0.20], [-35, 8, 0.32]].map do |dx, dy, o|
    %(<g clip-path="url(##{p}-text-mask)" transform="translate(#{dx} #{dy})" opacity="#{o}">\
<rect width="1000" height="500" fill="#F6B26B"/></g>)
  end.join
  main = ink(p, %(<rect width="1000" height="500" fill="#E8833A"/>))
  sprockets = (0..23).map { |i| x = 20 + i * 42; %(<rect x="#{x}" y="12" width="12" height="10" fill="#241D12" opacity="0.8"/><rect x="#{x}" y="478" width="12" height="10" fill="#241D12" opacity="0.8"/>) }.join
  carrier = %(<path d="#{CARRIER}" fill="none" stroke="#241D12" stroke-width="1" opacity="0.35" stroke-dasharray="8 6"/>)
  body = ghosts + main + hairlines("#241D12") + carrier + sprockets
  plate(7, "zoetrope_onion", "amber mark — onion-skin motion frames on the carrier curve",
        %(<rect width="1000" height="500" fill="#F6F1E3"/>), body)
end

# 08 — press proof: CMYK overprint with misregistration, registration marks, bars.
def p08
  p = "pl08"
  layer = lambda do |dx, dy, color, opacity|
    %(<g clip-path="url(##{p}-text-mask)" transform="translate(#{dx} #{dy})" style="mix-blend-mode:multiply">\
<rect width="1000" height="500" fill="#{color}" opacity="#{opacity}"/></g>)
  end
  body = layer.call(-9, -6, "#00AEEF", 0.9) + layer.call(9, -4, "#EC008C", 0.9) +
         layer.call(0, 9, "#FFF200", 0.9) + layer.call(0, 0, "#1A1A1A", 0.55)
  body += HAIRLINES.map { |w, d| %(<path d="#{d}" fill="none" stroke="#1A1A1A" stroke-width="#{w + 1.3}" opacity="0.28"/>) }.join
  body += hairlines("#FFFFFF")
  marks = [[60, 58], [940, 58], [60, 442], [940, 442]].map do |x, y|
    %(<g stroke="#1A1A1A" stroke-width="1.2" fill="none"><circle cx="#{x}" cy="#{y}" r="11"/>\
<path d="M#{x - 17} #{y} H#{x + 17} M#{x} #{y - 17} V#{y + 17}"/></g>)
  end.join
  bars = %w[#00AEEF #EC008C #FFF200 #1A1A1A #C8F55F #FFB999].each_with_index.map do |c, i|
    %(<rect x="#{50 + i * 29}" y="446" width="24" height="16" fill="#{c}" stroke="#1A1A1A" stroke-width="0.6"/>)
  end.join
  body += marks + bars
  plate(8, "cmyk_press", "amber mark — CMYK overprint proof with misregistration",
        %(<rect width="1000" height="500" fill="#FAF7F0"/>), body)
end

# 09 — pony meadow: pastel sky, rainbow behind the mark, pixel pony on the swoosh.
def p09
  p = "pl09"
  sky = %(<linearGradient id="pl09-sky" x1="0" y1="0" x2="0" y2="1">\
<stop offset="0" stop-color="#FFD9EC"/><stop offset="0.5" stop-color="#EAD9FF"/><stop offset="1" stop-color="#C9F0FF"/></linearGradient>)
  candy = %(<linearGradient id="pl09-ink" gradientUnits="userSpaceOnUse" x1="0" y1="120" x2="0" y2="290">\
<stop offset="0" stop-color="#F0559C"/><stop offset="0.55" stop-color="#8A4BFF"/><stop offset="1" stop-color="#0FA88A"/></linearGradient>)
  rainbow = %w[#FF5E5E #FF9D5C #FFE45C #7DFF8A #5CC8FF #8A7DFF].each_with_index.map do |c, i|
    %(<circle cx="500" cy="640" r="#{520 - i * 19}" fill="none" stroke="#{c}" stroke-width="19" opacity="0.55"/>)
  end.join
  rows = ["....MMMM........", "..MMMMMMM...MM..", "..MMEMMBBBBBBMM.", "..MMBBBBBBBBB.M.",
          "..BBBBBBBBBBB.M.", "..BBB.BBB..BB...", "..BB...BB..BB...", "..HH...HH..HH..."]
  colors = { "M" => "#FF8AC2", "B" => "#A05CFF", "E" => "#2A1533", "H" => "#2A1533" }
  pony = rows.each_with_index.flat_map do |row, ry|
    row.each_char.with_index.select { |ch, _| ch != "." }.map do |ch, rx|
      %(<rect x="#{rx * 4.5}" y="#{ry * 4.5}" width="4.5" height="4.5" fill="#{colors[ch]}"/>)
    end
  end.join
  pony = %(<g transform="translate(688 92) rotate(-2 720 114)">#{pony}</g>)
  r = Random.new(5709)
  twinkles = Array.new(7) do
    c = %w[#FFFFFF #FFF7B8 #FFC8E8][r.rand(0..2)]
    sparkle(r.rand(60.0..940.0).round(1), r.rand(30.0..110.0).round(1), r.rand(5.0..9.0).round(1), c, 0.9)
  end.join
  carrier = %(<path d="#{CARRIER}" fill="none" stroke="#FFFFFF" stroke-width="2" opacity="0.8"/>)
  body = rainbow + ink(p, %(<rect width="1000" height="500" fill="url(#pl09-ink)"/>)) +
         hairlines("#FFFFFF", { opacity: 0.95 }) + carrier + pony + twinkles
  plate(9, "pony_meadow", "amber mark — pastel sky, rainbow arc, pixel pony on the swoosh",
        %(<rect width="1000" height="500" fill="url(#pl09-sky)"/>), body, sky + candy)
end

# 10 — terminal sweep: phosphor signal ink, oscilloscope hairlines, scanlines.
def p10
  p = "pl10"
  phos = %(<linearGradient id="pl10-ink" gradientUnits="userSpaceOnUse" x1="0" y1="130" x2="0" y2="280">\
<stop offset="0" stop-color="#C8F55F"/><stop offset="0.6" stop-color="#7DB32E"/><stop offset="1" stop-color="#3F5E12"/></linearGradient>)
  grid_pat = %(<pattern id="pl10-grid" width="25" height="25" patternUnits="userSpaceOnUse"><circle cx="1" cy="1" r="0.8" fill="#14210F"/></pattern>)
  scan_pat = %(<pattern id="pl10-scan" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="4" height="2" fill="#000" opacity="0.25"/></pattern>)
  lines = HAIRLINES.map.with_index do |(w, d), i|
    y0 = d[/M50,(\d+)/, 1].to_i
    %(<path d="#{d}" fill="none" stroke="#C8F55F" stroke-width="#{w}" opacity="#{(0.9 - i * 0.06).round(2)}"/>\
<path d="M50 #{y0 - 4} V#{y0 + 4} M950 #{y0 - 54} V#{y0 - 46}" stroke="#C8F55F" stroke-width="#{w}" opacity="0.7"/>)
  end.join
  carrier = %(<path d="#{CARRIER}" fill="none" stroke="#C8F55F" stroke-width="1" opacity="0.35" stroke-dasharray="3 5"/>)
  cursor = %(<rect x="480" y="146" width="13" height="26" fill="#C8F55F"/>)
  body = %(<rect width="1000" height="500" fill="url(#pl10-grid)"/>)
  body += ink(p, %(<rect width="1000" height="500" fill="url(#pl10-ink)"/>)) + lines + carrier + cursor
  body += %(<rect width="1000" height="500" fill="url(#pl10-scan)"/>)
  plate(10, "terminal_sweep", "amber mark — phosphor signal ink on the oscilloscope swoosh",
        %(<rect width="1000" height="500" fill="#050705"/>), body, phos + grid_pat + scan_pat)
end

def write_reference
  grad = %(<radialGradient id="pl00-ink" gradientUnits="userSpaceOnUse" cx="500" cy="250" r="560">\
<stop offset="0" stop-color="#ffb999"/><stop offset="0.33" stop-color="#e6cce6"/>\
<stop offset="0.66" stop-color="#cce6cc"/><stop offset="1" stop-color="#99e6e6"/></radialGradient>)
  body = ink("pl00", %(<rect width="1000" height="500" fill="url(#pl00-ink)"/>)) + hairlines("#FFFFFF")
  File.write(File.join(OUT_DIR, "reference-original.svg"),
             svg_doc("00", "canonical amber mark — ink frozen, no animation", "", body, grad))
end

def write_index
  cells = PLATES.map do |pl|
    %(<figure><img src="plates/#{pl[:num]}_#{pl[:slug]}.svg" alt="#{pl[:title]}">\
<figcaption>#{pl[:num]} · #{pl[:slug].tr('_', ' ')}</figcaption></figure>)
  end.join
  html = <<~HTML
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <title>plur1bus plates — the amber mark, ten directions</title>
    <style>
      body { margin: 0; background: #17171a; color: #c9c9cf; font: 14px/1.4 sans-serif; padding: 24px 26px 40px; }
      h1 { font-size: 15px; font-weight: 600; letter-spacing: .04em; margin: 0 0 6px; color: #ececf2; }
      p.sub { margin: 0 0 18px; color: #8b8b93; }
      .ref { margin: 0 0 26px; }
      .ref img { width: 560px; display: block; background: #101013; border-radius: 4px; }
      .ref figcaption, figure figcaption { color: #8b8b93; font-size: 12px; margin-top: 4px; letter-spacing: .05em; text-transform: uppercase; }
      .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 26px; }
      figure { margin: 0; }
      figure img { width: 100%; display: block; background: #101013; border-radius: 4px; }
    </style></head><body>
    <h1>plur1bus plates — the amber&reg; mark, ten directions</h1>
    <p class="sub">Every plate keeps the canonical Caprasimo wordmark and the nine swoosh hairlines; the material, ground and grade around them change.</p>
    <figure class="ref"><img src="plates/reference-original.svg" alt="canonical amber mark"><figcaption>00 · reference — canonical mark, ink frozen</figcaption></figure>
    <div class="grid">#{cells}</div>
    </body></html>
  HTML
  File.write(File.join(PLATES_DIR, "all-plates.html"), html)
end

FileUtils.mkdir_p(OUT_DIR)
p01; p02; p03; p04; p05; p06; p07; p08; p09; p10
write_reference
write_index
puts "wrote #{PLATES.size} plates + reference + index under #{PLATES_DIR}"
