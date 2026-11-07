# frozen_string_literal: true

# Retrace /Users/mac/Downloads/image.jpg as vector SVG.
# Read the binarized PBM (P4), chain every black/white boundary edge into
# closed loops (directed with black on the right, so holes wind the other
# way), simplify each loop with Ramer-Douglas-Peucker at a small epsilon to
# keep the mark's rugged hand-drawn character, and emit one path filled
# black with fill-rule evenodd.

PBM = "/private/tmp/fetat-logo/image_bw.pbm"
OUT = File.expand_path("fetat.svg", __dir__)
EPSILON = 1.2

data = File.binread(PBM)
raise "not P4" unless data.start_with?("P4\n")

m = /\AP4\s+(\d+)\s+(\d+)\s/.match(data)
W, H = m[1].to_i, m[2].to_i
offset = m.end(0)
offset += 1 if data[offset - 1] != "\n" && data[offset] == "\n"
row_bytes = (W + 7) / 8
bits = data.byteslice(offset, row_bytes * H)
raise "short body (#{bits.bytesize} < #{row_bytes * H})" if bits.bytesize < row_bytes * H

GRID = Array.new(H) do |y|
  row = bits.byteslice(y * row_bytes, row_bytes).unpack("C*")
  Array.new(W) { |x| (row[x / 8] >> (7 - (x % 8))) & 1 }
end

black = ->(x, y) { x >= 0 && x < W && y >= 0 && y < H && GRID[y][x] == 1 }

# Boundary edges, black on the right of travel (lattice coords):
#   top edge    (x,y)   -> (x+1,y)     bottom edge (x+1,y+1) -> (x,y+1)
#   right edge  (x+1,y) -> (x+1,y+1)   left edge   (x,y+1)   -> (x,y)
edges = {}
(0...H).each do |y|
  (0...W).each do |x|
    next unless GRID[y][x] == 1
    unless black.(x, y - 1)
      (edges[[x, y]] ||= []) << [x + 1, y]
    end
    unless black.(x + 1, y)
      (edges[[x + 1, y]] ||= []) << [x + 1, y + 1]
    end
    unless black.(x, y + 1)
      (edges[[x + 1, y + 1]] ||= []) << [x, y + 1]
    end
    unless black.(x - 1, y)
      (edges[[x, y + 1]] ||= []) << [x, y]
    end
  end
end

# Chain edges into loops. At a lattice point with two outgoing edges (a
# diagonal saddle), take the sharpest right turn so the two loops stay
# apart; winding is uniform because black is always on the right.
def turn_dir(prev_dir, next_point, from)
  ndx = next_point[0] - from[0]
  ndy = next_point[1] - from[1]
  (ndx - prev_dir[0]) * 2 + (ndy - prev_dir[1])
end

loops = []
until edges.empty?
  start = edges.keys.first
  loop_pts = []
  from = start
  dir = nil
  loop do
    outs = edges[from]
    raise "dangling edge at #{from.inspect}" if outs.nil? || outs.empty?
    pt = dir.nil? ? outs.first : outs.min_by { |o| turn_dir(dir, o, from) }
    dir = [pt[0] - from[0], pt[1] - from[1]]
    outs.delete(pt)
    edges.delete(from) if outs.empty?
    loop_pts << pt
    break if pt == start
    from = pt
  end
  loops << loop_pts
end

# Ramer-Douglas-Peucker on a closed loop: start from the point farthest
# from loop[0], walk both ways so the seam is never at a corner.
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

simplified = loops.map do |l|
  far = l.each_with_index.max_by { |p, i| (l[0][0] - p[0])**2 + (l[0][1] - p[1])**2 }[1]
  rot = l.rotate(far)
  rdp(rot + [rot[0]], EPSILON)
end

total_pts = simplified.sum(&:length)
paths = simplified.map do |l|
  d = l.each_with_index.map do |(x, y), i|
    "#{i.zero? ? 'M' : 'L'}#{x} #{y}"
  end.join << "Z"
end
svg = <<~SVG
  <?xml version="1.0" encoding="UTF-8"?>
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{W} #{H}" role="img" aria-label="FETAT">
    <title>FETAT</title>
    <path fill="#000" fill-rule="evenodd" d="#{paths.join(" ")}"/>
  </svg>
SVG

File.write(OUT, svg)
puts "loops=#{loops.length} kept #{total_pts}/#{loops.sum(&:length)} points -> #{OUT}"
