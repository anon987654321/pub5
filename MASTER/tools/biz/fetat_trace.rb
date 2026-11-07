# frozen_string_literal: true

# Retrace /Users/mac/Downloads/image.jpg as vector SVG: outline centerlines
# stroked at one uniform width, ragged lines. Read the binarized PBM (P4),
# thin the ink to its skeleton (Zhang-Suen), chain the skeleton into lines,
# simplify each with Ramer-Douglas-Peucker at a small epsilon (the ragged hand
# of the drawing survives; only stair-steps go), and emit one group of paths
# stroked black at the drawing's own dominant thickness.

# The pipeline is self-contained: the source art is image.jpg beside this
# script; binarize with ImageMagick into the machine's tmp and trace it.
SRC_IMAGE = File.expand_path("fetat_image.jpg", __dir__)
require "open3"
require "tmpdir"
LOGO_TMP = File.join(Dir.tmpdir, "fetat-logo")
PBM = File.join(LOGO_TMP, "image_bw.pbm")
Dir.mkdir(LOGO_TMP) unless File.directory?(LOGO_TMP)
unless File.file?(PBM)
  _o, _e, st = Open3.capture3("magick", SRC_IMAGE, "-colorspace", "gray",
                               "-threshold", "60%", "-resize", "624x416", PBM)
  raise "binarization failed" unless st.success?
end
OUT = File.expand_path("fetat.svg", __dir__)
EPSILON = 1.4

def read_pbm(path)
  data = File.binread(path)
  raise "not P4" unless data.start_with?("P4\n")
  m = /\AP4\s+(\d+)\s+(\d+)\s/.match(data)
  w, h = m[1].to_i, m[2].to_i
  off = m.end(0)
  off += 1 if data[off] == "\n"
  row_bytes = (w + 7) / 8
  bits = data.byteslice(off, row_bytes * h)
  raise "short body (#{bits.bytesize} < #{row_bytes * h})" if bits.bytesize < row_bytes * h
  grid = Array.new(h) do |y|
    row = bits.byteslice(y * row_bytes, row_bytes).unpack("C*")
    Array.new(w) { |x| (row[x / 8] >> (7 - (x % 8))) & 1 }
  end
  [w, h, grid]
end

W, H, G = read_pbm(PBM)
black = ->(x, y) { x >= 0 && x < W && y >= 0 && y < H && G[y][x] == 1 }

# Zhang-Suen thinning down to a one-pixel skeleton.
def thin!(g)
  h = g.size
  w = g[0].size
  n = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
  pass = 0
  loop do
    pass += 1
    changed = false
    2.times do |sub|
      marks = []
      each_ink(g) do |x, y|
        a, b = 0, 0
        nb = n.map { |dx, dy| g[(y + dy) % h][(x + dx) % w] }
        8.times { |i| a += (nb[i] == 0 && nb[(i + 1) % 8] == 1 ? 1 : 0) }
        8.times { |i| b += nb[i] }
        p2, p4, p6, p8 = nb[0], nb[2], nb[4], nb[6]
        if a == 1 && b.between?(2, 6) &&
           (sub.zero? ? p2 * p4 * p6 : p2 * p4 * p8).zero? &&
           (sub.zero? ? p4 * p6 * p8 : p2 * p6 * p8).zero?
          marks << [x, y]
        end
      end
      changed = true unless marks.empty?
      marks.each { |x, y| g[y][x] = 0 }
    end
    break if !changed
    break if pass > 30
  end
end

def each_ink(g)
  g.each_index do |y|
    row = g[y]
    row.each_index { |x| yield x, y if row[x] == 1 }
  end
end

sk = G.map(&:dup)
thin!(sk)
skeleton_pts = []
each_ink(sk) { |x, y| skeleton_pts << [x, y] }
abort "empty skeleton" if skeleton_pts.empty?

nb = lambda do |x, y|
  [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
    .map { |dx, dy| (sk[y + dy] && sk[y + dy][x + dx]) == 1 }
    .count(true)
end

# Chain the skeleton: from each endpoint walk while the way forks nowhere;
# then close whatever circuits remain.
visited = Hash.new(false)
chains = []
skeleton_pts.each do |(x, y)|
  next if visited[[x, y]] || nb.(x, y) != 1
  chain = [[x, y]]
  visited[[x, y]] = true
  loop do
    cx, cy = chain.last
    nxt = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
          .filter_map { |dx, dy| [cx + dx, cy + dy] }
          .select { |p| (sk[p[1]] && sk[p[1]][p[0]]) == 1 && !visited[p] }
    break if nxt.empty?
    chain << nxt.first
    visited[nxt.first] = true
  end
  chains << chain
end
skeleton_pts.each do |(x, y)|
  next if visited[[x, y]] || nb.(x, y) > 2
  chain = [[x, y]]
  visited[[x, y]] = true
  loop do
    cx, cy = chain.last
    nxt = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
          .filter_map { |dx, dy| [cx + dx, cy + dy] }
          .select { |p| (sk[p[1]] && sk[p[1]][p[0]]) == 1 && !visited[p] }
    break if nxt.empty?
    chain << nxt.first
    visited[nxt.first] = true
  end
  chains << chain if chain.length > 1
end

def rdp(pts, epsilon)
  return pts if pts.length < 3
  keep = Array.new(pts.length, false)
  keep[0] = keep[-1] = true
  stack = [[0, pts.length - 1]]
  until stack.empty?
    a, b = stack.pop
    next if b <= a + 1
    ax, ay = pts[a]
    bx, by = pts[b]
    dx, dy = bx - ax, by - ay
    len = Math.sqrt(dx * dx + dy * dy)
    worst, wi = 0.0, nil
    ((a + 1)...b).each do |i|
      px, py = pts[i]
      d = len.zero? ? Math.sqrt((px - ax)**2 + (py - ay)**2)
                    : ((dy * (px - ax) - dx * (py - ay)).abs / len)
      if d > worst
        worst, wi = d, i
      end
    end
    if worst > epsilon
      keep[wi] = true
      stack << [a, wi] << [wi, b]
    end
  end
  pts.each_index.select { |i| keep[i] }.map { |i| pts[i] }
end

# Drop specks, keep everything a reader can see.
chains.reject! { |c| c.length < 6 }
simplified = chains.map { |c| rdp(c, EPSILON) }

# One width: the ink's own dominant half-thickness, doubled.
# Distance to nearest white, two-pass chamfer, sampled over the skeleton.
dt = Array.new(H) { Array.new(W, 999) }
(0...H).each { |y| (0...W).each { |x| dt[y][x] = black.(x, y) ? 1 : 0 } }
(0...H).each { |y| (0...W).each { |x| c = dt[y][x]; next if c.zero?
  c2 = y.positive? ? dt[y - 1][x] + 1 : 999
  c3 = x.positive? ? dt[y][x - 1] + 1 : 999
  dt[y][x] = [c, c2, c3].min } }
((H - 1).downto(0)).each { |y| ((W - 1).downto(0)).each { |x| c = dt[y][x]; next if c.zero?
  c2 = y < H - 1 ? dt[y + 1][x] + 1 : 999
  c3 = x < W - 1 ? dt[y][x + 1] + 1 : 999
  dt[y][x] = [c, c2, c3].min } }
samples = skeleton_pts.map { |x, y| dt[y][x] }.sort
width = [(samples[samples.length * 19 / 20] || 3) * 2 - 1, 3].max

min_x = simplified.map { |l| l.map { |p| p[0] }.min }.min
max_x = simplified.map { |l| l.map { |p| p[0] }.max }.max
min_y = simplified.map { |l| l.map { |p| p[1] }.min }.min
max_y = simplified.map { |l| l.map { |p| p[1] }.max }.max
pad = width * 2

paths = simplified.map do |l|
  l.each_with_index.map { |(x, y), i| "#{i.zero? ? 'M' : 'L'}#{x} #{y}" }.join
end
svg = <<~SVG
  <?xml version="1.0" encoding="UTF-8"?>
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="#{min_x - pad} #{min_y - pad} #{max_x - min_x + pad * 2} #{max_y - min_y + pad * 2}" role="img" aria-label="FETAT">
    <title>FETAT</title>
    <g fill="none" stroke="#000" stroke-width="#{width}" stroke-linecap="round" stroke-linejoin="round">
      #{paths.map { |d| %(<path d="#{d}"/>) }.join("\n      ")}
    </g>
  </svg>
SVG

File.write(OUT, svg)
puts "skeleton pts=#{skeleton_pts.length} chains=#{chains.length} width=#{width} -> #{OUT}"

# debug
