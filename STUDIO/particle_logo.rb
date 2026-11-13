# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

# The plur1bus particle mark — one engine for every surface that shows a logo.
#
# Reality is assembled from many small carriers; the mark is not a solid skin
# but a field of them. The same source answers three surfaces with one truth:
# an alpha film for the demo video overlay, a still frame for a raster logo,
# and a homes JSON (point cloud inside the glyph geometry) that the browser
# engines under RAILS/__shared and MASTER/web animate themselves.
#
# The material is greyscale particle stipple with sparse signal carriers
# (MASTER/data/tokens.yml visual_identity: material greyscale_particle_stipple,
# signal #C8F55F far under max_highlight_area_fraction). Colour is a semantic
# accent, never the substance; the mark is geometry, so it needs no webfont.
#
# Everything is a fixed function of (source, seed, size, count): the same
# inputs render byte-identical frames, and a shipped mark can be regenerated
# from its generator instead of being hand-edited in place.
module Studio
  module ParticleLogo
    class Unavailable < StandardError; end

    INK_DARK = "#101010"       # tokens signal_ink
    INK_LIGHT = "#8A8A8A"      # greyscale top of the carrier ramp
    SIGNAL = "#C8F55F"         # tokens visual_identity.signal
    MAX_SIGNAL_FRACTION = 0.08 # tokens max_highlight_area_fraction

    AMBER_REFERENCE = File.expand_path("../RAILS/amber/__logo/plates/reference-original.svg", __dir__)

    # An SVG mark reduced to the geometry that can carry ink: the glyph paths
    # and the placed <use> instances inside one viewBox. Sampling happens in
    # the source's own units, so a caller scales the whole mark, not the paths.
    class Source
      GLYPH_TAG = /<(path|use)\b[^>]*>/i

      attr_reader :view_box, :name

      def initialize(svg:, name: "mark")
        @svg = svg
        @name = name
        box = svg[/viewBox="([^"]+)"/, 1] or
          raise ArgumentError, "mark SVG has no viewBox"
        values = box.split(/[\s,]+/).map { |v| Float(v) }
        raise ArgumentError, "viewBox needs four numbers" unless values.length == 4
        raise ArgumentError, "viewBox width and height must be positive" if values[2] <= 0 || values[3] <= 0

        @view_box = values
        @defs = @svg[/<defs>(.*?)<\/defs>/m, 1].to_s
        @geometry = ink_geometry
        raise ArgumentError, "mark SVG carries no glyph geometry" if @geometry.empty?
      end

      def self.from_file(path, name: nil)
        path = File.expand_path(path)
        raise ArgumentError, "mark SVG not found: #{path}" unless File.file?(path)

        new(svg: File.read(path), name: name || File.basename(path, ".svg"))
      end

      # The glyph <path> defs and the <use> placements, minus the nine white
      # hairlines (stroke="#FFFFFF"): the field is the letters' interiors, not
      # the decorative lines. A mark with no <use> keeps its filled paths.
      def ink_geometry
        defs = @svg[/<defs>(.*?)<\/defs>/m, 1].to_s
        uses = @svg.scan(/<use\b[^>]*href="#[^"]+"[^>]*>/i).reject { |u| u.include?("stroke") }
        return uses unless uses.empty?

        defs.scan(/<path\b[^>]*d="[^"]+"[^>]*>/i).reject { |p| p.include?("stroke") }
      end

      # Rasterize the ink to a width x height grey mask and return the inside
      # pixels in mark-local coordinates. rsvg-convert is the SVG authority the
      # browser and the amber __logo generator already agree with.
      def mask(width:, height:)
        svg = <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="#{@view_box.join(' ')}">
            <rect x="#{@view_box[0]}" y="#{@view_box[1]}" width="#{@view_box[2]}" height="#{@view_box[3]}" fill="#FFFFFF"/>
            <defs>#{@defs}</defs>
            <g fill="#000000">#{@geometry.join}</g>
          </svg>
        SVG
        Dir.mktmpdir("particle-logo-mask") do |dir|
          svg_path = File.join(dir, "mask.svg")
          png_path = File.join(dir, "mask.png")
          raw_path = File.join(dir, "mask.raw")
          File.write(svg_path, svg)
          run("rsvg-convert", "-w", width.to_s, "-h", height.to_s, svg_path, "-o", png_path)
          run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", png_path,
              "-pix_fmt", "gray", "-f", "rawvideo", raw_path)
          bytes = File.binread(raw_path)
          expected = width * height
          raise Unavailable, "mask raster is #{bytes.bytesize} bytes, expected #{expected}" unless bytes.bytesize == expected

          inside = []
          bytes.each_byte.with_index do |value, index|
            inside << [index % width, index / width] if value < 128
          end
          inside
        end
      end

      private

      def run(*command)
        _out, err, status = Open3.capture3(*command)
        return if status.success?

        raise Unavailable, "#{command.first} failed: #{err.lines.last.to_s.strip}"
      end
    end

    # A deterministic point cloud inside a mark. Homes are chosen once from the
    # mask with a seeded shuffle, so the same (source, size, count, seed) always
    # yields the same carriers in the same places.
    class Field
      attr_reader :homes, :width, :height

      def initialize(source, width:, height:, count:, seed: 0, tone: :dark)
        @width = Integer(width)
        @height = Integer(height)
        @count = Integer(count)
        @tone = tone.to_sym
        raise ArgumentError, "unknown tone #{tone}" unless %i[dark light].include?(@tone)
        raise ArgumentError, "field size must be positive" if @width <= 0 || @height <= 0
        raise ArgumentError, "field needs at least one carrier" if @count <= 0

        @rng = Rng.new(seed)
        @homes = sample(source.mask(width: @width, height: @height))
        raise Unavailable, "mark rasterized to no ink at #{@width}x#{@height}" if @homes.empty?

        @starts = build_starts
      end

      def size = @homes.length

      # The film frame at phase t in [0, 1): carriers fly in from a seeded
      # scatter and settle on the mark, then hold with a slow drift and a
      # signal band that propagates across the field. Gather occupies the first
      # GATHER fraction; the rest is the settled field the video loops.
      GATHER = 0.4

      def frame(t)
        phase = t - t.floor
        gather = phase < GATHER
        settle = gather ? ease(phase / GATHER) : 1.0
        drift_phase = phase * 2.0 * Math::PI
        circles = @homes.each_with_index.map do |(home_x, home_y, radius, tone, signal), index|
          start = @starts[index]
          x = start[0] + (home_x - start[0]) * settle
          y = start[1] + (home_y - start[1]) * settle
          if gather
            x += Math.sin(drift_phase + index) * 1.5 * (1.0 - settle)
            y += Math.cos(drift_phase + index) * 1.5 * (1.0 - settle)
          else
            x += Math.sin(drift_phase + index * 0.7) * 0.6
            y += Math.cos(drift_phase * 0.8 + index * 0.5) * 0.6
          end
          fill, opacity = carrier_paint(index, tone, signal, settle, phase)
          r = radius * (0.5 + 0.5 * settle)
          format(%(<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s" fill-opacity="%.3f"/>),
                 x, y, r, fill, opacity)
        end
        <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{@width} #{@height}" width="#{@width}" height="#{@height}">
            #{circles.join}
          </svg>
        SVG
      end

      private

      def sample(inside)
        picked = if @count >= inside.length
                   inside
                 else
                   stride = inside.length.to_f / @count
                   Array.new(@count) { |i| inside[(i * stride).floor] }
                 end
        base_radius = [1.0, @height / 46.0].max
        signal_budget = [1, (@count * MAX_SIGNAL_FRACTION).round].max
        picked.each_with_index.map do |(x, y), index|
          radius = base_radius * (0.6 + @rng.rand * 0.8)
          signal = index < signal_budget
          [x.to_f, y.to_f, radius, @tone, signal]
        end
      end

      # start offsets: a seeded scatter around the mark, so carriers fly in.
      def build_starts
        @homes.map do |(x, y, *)|
          angle = @rng.rand * 2.0 * Math::PI
          reach = @width * (0.25 + @rng.rand * 0.6)
          [x + Math.cos(angle) * reach, y + Math.sin(angle) * reach * 0.5]
        end
      end

      def carrier_paint(index, tone, signal, settle, phase)
        return [SIGNAL, settle] if signal && signal_lit?(index, phase)

        if tone == :light
          # Light carriers for a dark ground (the demo video): a greyscale ramp
          # from near-white ink down to the mid-grey carrier.
          level = (0.94 - (index % 7) / 16.0).clamp(0.42, 0.98)
          grey = (level * 255).round
        else
          # Dark carriers for a light ground (a page): near-black ink with a
          # little variance so the field reads as many, not one.
          shade = (0.06 + (index % 7) / 12.0).clamp(0.06, 0.62)
          grey = (shade * 255).round
        end
        [format("#%02X%02X%02X", grey, grey, grey), 0.35 + 0.65 * settle]
      end

      # The signal is propagating state, not ornament: a narrow band travels
      # across the field, lighting carriers as it passes.
      def signal_lit?(index, phase)
        span = 0.12
        centre = (phase - GATHER) / (1.0 - GATHER)
        return false if centre.negative?

        position = index.to_f / size
        (position - centre).abs < span
      end

      def ease(value) = value * value * (3.0 - 2.0 * value)
    end

    # Deterministic integer LCG. Ruby's Kernel#rand is seeded globally and is
    # not part of a render's identity, so the field carries its own stream.
    class Rng
      def initialize(seed)
        @state = (Integer(seed) ^ 0x9E3779B9) & 0xFFFF_FFFF
        @state = 1 if @state.zero?
      end

      def rand
        @state = (1_664_525 * @state + 1_013_904_223) & 0xFFFF_FFFF
        @state.to_f / 0x1_0000_0000
      end
    end

    module_function

    # Render the alpha film as PNG frames under out_dir. Returns the frame paths
    # in order. Every frame is a still SVG rasterized by rsvg-convert, so the
    # film is reproducible and needs no GPU.
    def render_frames(source, out_dir:, frames:, size:, count: 900, seed: 0, tone: :dark, prefix: "logo")
      width, height = fit(size, source.view_box)
      field = Field.new(source, width: width, height: height, count: count, seed: seed, tone: tone)
      FileUtils.mkdir_p(out_dir)
      paths = (0...frames).map do |index|
        svg_path = File.join(out_dir, "#{prefix}-#{format('%04d', index)}.svg")
        png_path = File.join(out_dir, "#{prefix}-#{format('%04d', index)}.png")
        File.write(svg_path, field.frame(index.to_f / frames))
        _out, err, status = Open3.capture3("rsvg-convert", svg_path, "-o", png_path)
        raise Unavailable, "rsvg-convert failed: #{err.lines.last.to_s.strip}" unless status.success?

        png_path
      end
      paths
    end

    # The homes JSON a browser engine animates itself: mark-local carrier
    # positions plus the field's declared size, so the web layer and the film
    # draw the same cloud.
    def homes_json(source, size:, count: 900, seed: 0, tone: :dark)
      width, height = fit(size, source.view_box)
      field = Field.new(source, width: width, height: height, count: count, seed: seed, tone: tone)
      JSON.generate(
        "mark" => source.name,
        "width" => width,
        "height" => height,
        "signal" => SIGNAL,
        "ink" => INK_DARK,
        "tone" => tone.to_s,
        "max_signal_fraction" => MAX_SIGNAL_FRACTION,
        "homes" => field.homes.map { |x, y, radius, _tone, signal| [x.round(2), y.round(2), radius.round(2), signal ? 1 : 0] }
      )
    end

    # Scale a source viewBox so its width becomes size px, keeping the aspect.
    def fit(size, view_box)
      width = Integer(size)
      raise ArgumentError, "size must be positive" if width <= 0

      height = (width * view_box[3] / view_box[2]).round
      [width, [height, 1].max]
    end

    # The demo video: dilla's own visualizer (showwaves over showcqt, the two
    # filters STUDIO/dilla render_video already stacks) with the animated
    # plur1bus mark pinned in the top-left corner. The logo film is rendered
    # first, then ffmpeg overlays it; no frame is drawn by a second truth.
    DEFAULT_MARGIN = 32

    def render_demo(source:, audio:, out:, size: 420, count: 900, seed: 0, fps: 12,
                    margin: DEFAULT_MARGIN, work_dir: nil, tone: :light)
      audio = File.expand_path(audio)
      raise ArgumentError, "demo audio not found: #{audio}" unless File.file?(audio)

      duration = probe_duration(audio)
      frames = [(duration * fps).ceil, 1].max
      dir = work_dir || Dir.mktmpdir("particle-logo-demo")
      begin
        render_frames(source, out_dir: dir, frames: frames, size: size, count: count,
                              seed: seed, tone: tone, prefix: "logo")
        compose_demo(dir, audio, out, fps: fps, margin: margin, frames: frames)
      ensure
        FileUtils.remove_entry(dir) if work_dir.nil? && Dir.exist?(dir)
      end
      out
    end

    def compose_demo(dir, audio, out, fps:, margin:, frames:)
      filter = "[0:a]showwaves=s=1280x360:mode=cline:colors=cyan|magenta:rate=#{fps}[w];" \
               "[0:a]showcqt=s=1280x360:fps=#{fps}[c];[w][c]vstack[bg];" \
               "[bg][1:v]overlay=#{margin}:#{margin}:shortest=1[out]"
      command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", audio,
        "-framerate", fps.to_s, "-i", File.join(dir, "logo-%04d.png"),
        "-filter_complex", filter,
        "-map", "[out]", "-map", "0:a",
        "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-shortest", out
      ]
      _out, err, status = Open3.capture3(*command)
      raise Unavailable, "ffmpeg demo compose failed: #{err.lines.last(3).join.strip}" unless status.success?

      raise Unavailable, "ffmpeg produced no demo at #{out}" unless File.file?(out)

      out
    end

    def probe_duration(audio)
      out, err, status = Open3.capture3(
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=nk=1:nw=1", audio
      )
      raise Unavailable, "ffprobe failed: #{err.lines.last.to_s.strip}" unless status.success?

      Float(out.strip)
    rescue ArgumentError, TypeError
      raise Unavailable, "could not read the demo audio duration"
    end

    # --- CLI -----------------------------------------------------------------

    def run_cli(argv)
      options = { size: 420, count: 900, seed: 0, frames: 48, tone: :dark, margin: DEFAULT_MARGIN }
      source_path = AMBER_REFERENCE
      mode = :demo
      parser = OptionParser.new do |p|
        p.banner = "usage: ruby particle_logo.rb [--demo AUDIO --out FILE | --film DIR | --still FILE | --homes FILE] [options]"
        p.on("--source SVG", "mark SVG (default: amber reference)") { |v| source_path = v }
        p.on("--demo AUDIO", "compose a demo video over this audio") { |v| mode = :demo; options[:audio] = v }
        p.on("--film DIR", "write the logo PNG film here") { |v| mode = :film; options[:dir] = v }
        p.on("--still FILE", "write one settled frame (SVG) here") { |v| mode = :still; options[:file] = v }
        p.on("--homes FILE", "write the browser homes JSON here") { |v| mode = :homes; options[:file] = v }
        p.on("--out FILE", "demo output path") { |v| options[:out] = v }
        p.on("--size N", "mark width in px") { |v| options[:size] = Integer(v) }
        p.on("--count N", "carrier count") { |v| options[:count] = Integer(v) }
        p.on("--seed N", "field seed") { |v| options[:seed] = Integer(v) }
        p.on("--frames N", "film frame count") { |v| options[:frames] = Integer(v) }
        p.on("--fps N", "demo frame rate") { |v| options[:fps] = Integer(v) }
        p.on("--margin N", "demo overlay margin in px") { |v| options[:margin] = Integer(v) }
        p.on("--tone dark|light", "carrier tone") { |v| options[:tone] = v.to_sym }
        p.on("-h", "--help", "this help") { puts p; return 0 }
      end
      parser.parse!(argv)

      source = Source.from_file(source_path)
      case mode
      when :film
        paths = render_frames(source, out_dir: options[:dir], frames: options[:frames],
                                      size: options[:size], count: options[:count],
                                      seed: options[:seed], tone: options[:tone])
        puts "particle logo: #{paths.length} frames -> #{options[:dir]}"
      when :still
        width, height = fit(options[:size], source.view_box)
        field = Field.new(source, width: width, height: height, count: options[:count],
                                  seed: options[:seed], tone: options[:tone])
        File.write(options[:file], field.frame(0.7))
        puts "particle logo: still -> #{options[:file]}"
      when :homes
        File.write(options[:file], homes_json(source, size: options[:size], count: options[:count],
                                                      seed: options[:seed], tone: options[:tone]))
        puts "particle logo: homes -> #{options[:file]}"
      else
        raise ArgumentError, "--demo needs --out FILE" if options[:out].to_s.empty?
        raise ArgumentError, "--demo needs AUDIO" if options[:audio].to_s.empty?

        render_demo(source: source, audio: options[:audio], out: options[:out],
                    size: options[:size], count: options[:count], seed: options[:seed],
                    fps: options.fetch(:fps, 12), margin: options[:margin], tone: options[:tone])
        puts "particle logo: demo -> #{options[:out]}"
      end
      0
    rescue Unavailable, ArgumentError => e
      warn "particle logo: #{e.message}"
      1
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "optparse"
  exit(Studio::ParticleLogo.run_cli(ARGV))
end
