# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"
require "tmpdir"
require "vips"

require_relative "../replicate/subprocess"

begin
  require_relative "../postpro/depth"
rescue LoadError
  # Without the depth binding the warp falls back to postpro's own cues.
end

module Studio
  module Visual
    # Operations no camera performs, run on a subject's filmed clips with
    # ffmpeg and vips alone.
    #
    # Every break in moving-image history came from misusing the apparatus
    # rather than improving it: Muybridge's tripwire rows, Marey's single plate,
    # the slit-scan in 2001, Rybczynski's thirty-six loops in one room. A
    # generative model learns from human footage and interpolates inside it, so
    # it cannot supply the break. It can only work on what these pieces hand it.
    #
    # Each piece isolates one such break, and each is cheap enough to throw
    # away:
    #
    #   slit_scan     one frame reads its columns from sixty different moments,
    #                 so a body becomes a ribbon of its own time.
    #   motion_draw   every frame is the running average of all frames before
    #                 it: an exposure that never closes.
    #   envelope_cut  segment lengths follow the energy of the bed rather than a
    #                 beat grid, so the cut lands where the sound does.
    class Apparatus
      WIDTH = 1080
      HEIGHT = 1920
      FPS = 24
      SECONDS = 10
      # Frames of time the shear spans across the width, and the column strip
      # copied per step. A wider strip is faster and coarser.
      SHEAR = 60
      STRIP = 6
      # The shear assembles at a quarter of the delivery size; the encode
      # upscales. Full-size assembly costs twenty times as much for detail the
      # shear destroys anyway.
      ASSEMBLY = 0.25
      AUDIO = File.expand_path("../dilla/dilla.wav", __dir__)
      # How far the depth warp pushes in, as a fraction of frame width, and how
      # many poses a chronophotograph holds.
      PUSH = 0.30
      POSES = 12

      def initialize(subject:, directory: nil, audio: AUDIO, seconds: SECONDS, shear: SHEAR)
        @subject = subject.to_s
        @directory = directory || __dir__
        @audio = audio
        @seconds = seconds
        @shear = shear
      end

      def run
        clips = source_clips
        raise "no filmed clips for #{@subject} in #{@directory}" if clips.empty?

        pieces = {
          "slit_scan" => slit_scan(clips.first),
          "dual_slit" => dual_slit(clips.first, clips.last),
          "motion_draw" => motion_draw(clips.first),
          "chronophoto" => chronophoto(clips.first),
          "envelope_cut" => envelope_cut(clips),
        }
        still = latest_still
        pieces["depth_warp"] = depth_warp(still) if still
        pieces
      end

      # The newest developed still for this subject, if one is on disk.
      def latest_still
        Dir.glob(File.join(@directory, "postpro_*#{@subject}*.png")).max_by { |path| File.mtime(path) }
      end

      # The newest four takes, in the order they were filmed. Older takes stay
      # on disk for comparison and must not enter a new piece.
      def source_clips
        Dir.glob(File.join(@directory, "#{@subject}_film_*.mp4"))
           .sort_by { |path| File.mtime(path) }
           .last(4)
      end

      # A moving slit: output frame t takes column x from frame t plus the
      # offset that column implies. Frames come back through vips, because the
      # operation is per-column and ffmpeg has no expression that reaches
      # across frames by column.
      def slit_scan(clip, out: output_path("slit_scan"))
        Dir.mktmpdir("slit") do |tmp|
          small = [(WIDTH * ASSEMBLY).round, (HEIGHT * ASSEMBLY).round]
          frames = extract_frames(clip, tmp, small)
          raise "no frames decoded from #{clip}" if frames.empty?

          shots = File.join(tmp, "out")
          FileUtils.mkdir_p(shots)
          width, height = small
          steps = (width.to_f / STRIP).ceil

          frames.each_with_index do |frame, index|
            image = vips_image(frame)
            (0...steps).each do |step|
              x = step * STRIP
              take = [STRIP, width - x].min
              source = frames[(index + (step * @shear / steps)) % frames.length]
              image = image.insert(vips_image(source).crop(x, 0, take, height), x, 0)
            end
            image.write_to_file(File.join(shots, format("o_%05d.png", index)))
          end

          encode(File.join(shots, "o_%05d.png"), out, upscale: true)
        end
        finish("slit_scan", out, "shear" => @shear, "strip" => STRIP, "clip" => clip)
      end

      # A camera that never existed. One still plus a depth plane yields
      # parallax as the lens pushes in: near pixels move further than far ones,
      # which a still cannot do and a flat zoom cannot fake.
      def depth_warp(still, out: output_path("depth_warp"))
        image = Vips::Image.new_from_file(still, access: :random)
        base = fitted(image)
        plane = depth_plane(base)
        coords = Vips::Image.xyz(base.width, base.height)
        x = coords[0].cast("float")
        y = coords[1].cast("float")
        centre_x = base.width / 2.0
        centre_y = base.height / 2.0
        frames = (@seconds * FPS).round

        Dir.mktmpdir("warp") do |tmp|
          shots = Dir.mktmpdir("frames", tmp)
          frames.times do |index|
            phase = index.to_f / frames
            push = 0.02 + (PUSH * phase**2)
            sway = 0.015 * Math.sin(phase * 2 * Math::PI)
            dx = ((x - centre_x) * push * plane) + (plane * (sway * base.width))
            dy = (y - centre_y) * push * plane * 0.35
            index_image = Vips::Image.bandjoin([x + dx, y + dy]).cast("float")
            base.mapim(index_image).write_to_file(File.join(shots, format("o_%05d.png", index)))
          end
          encode(File.join(shots, "o_%05d.png"), out)
        end
        finish("depth_warp", out, "still" => still, "push" => PUSH)
      end

      # Two takes, one surface. Columns left of a sweeping edge read from the
      # first clip, columns right read from the second, and both are sheared
      # through time. Neither take survives as itself.
      def dual_slit(first, second, out: output_path("dual_slit"))
        size = [(WIDTH * ASSEMBLY).round, (HEIGHT * ASSEMBLY).round]
        width, height = size
        steps = (width.to_f / STRIP).ceil

        Dir.mktmpdir("dual") do |tmp|
          left = extract_frames(first, tmp, size)
          right = extract_frames(second, tmp, size)
          frames = [left.length, right.length].min
          raise "no frames decoded for the dual slit" if frames.zero?

          shots = File.join(tmp, "out")
          FileUtils.mkdir_p(shots)
          frames.times do |index|
            edge = 0.15 + (0.70 * index / frames)
            image = vips_image(left[index])
            steps.times do |step|
              x = step * STRIP
              take = [STRIP, width - x].min
              source = (x.to_f / width) < edge ? left : right
              frame = vips_image(source[(index + (step * @shear / steps)) % frames])
              image = image.insert(frame.crop(x, 0, take, height), x, 0)
            end
            image.write_to_file(File.join(shots, format("o_%05d.png", index)))
          end
          encode(File.join(shots, "o_%05d.png"), out, upscale: true)
        end
        finish("dual_slit", out, "first" => first, "second" => second, "shear" => @shear)
      end

      # Marey's plate: one surface, many moments. Each sampled pose is stacked
      # only where the subject moved, so the body repeats and the room stays
      # still. A single frame that holds twelve seconds.
      def chronophoto(clip, out: output_path("chronophoto", ext: "png"), poses: POSES)
        Dir.mktmpdir("chrono") do |tmp|
          frames = extract_frames(clip, tmp, [(WIDTH * ASSEMBLY).round, (HEIGHT * ASSEMBLY).round])
          raise "no frames decoded from #{clip}" if frames.empty?

          picks = (0...poses).map { |i| frames[(i * frames.length / poses).floor] }
          base = vips_image(picks.first)
          plate = base
          picks.drop(1).each do |path|
            frame = vips_image(path)
            moved = (frame - base).abs.colourspace("b-w").linear(1.0 / 24.0, 0.0)
            mask = (moved > 0.06).ifthenelse(1.0, 0.0).gaussblur(0.8)
            seen = frame * mask.bandjoin([mask, mask])
            plate = (plate > seen).ifthenelse(plate, seen)
          end
          plate.resize(WIDTH.to_f / plate.width).write_to_file(out)
        end
        finish("chronophoto", out, "clip" => clip, "poses" => poses)
      end

      # Exposure that never closes. `tblend=average` keeps the running mean, so
      # anything that moves leaves a trace and anything still stays solid.
      def motion_draw(clip, out: output_path("motion_draw"))
        argv = [
          "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
          "-i", clip, "-t", @seconds.to_s,
          "-vf", "scale=#{WIDTH}:#{HEIGHT}:force_original_aspect_ratio=increase," \
                 "crop=#{WIDTH}:#{HEIGHT},fps=#{FPS},tblend=all_mode=average," \
                 "eq=contrast=1.08:saturation=0.8:gamma=1.02,vignette=PI/5",
          "-an", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", out
        ]
        shell(argv)
        finish("motion_draw", out, "exposure" => "running average", "clip" => clip, "argv" => argv)
      end

      # Segment lengths from the bed's own energy. Each boundary sits on a rise,
      # so the picture changes when the music does rather than on a count. The
      # last boundary stops at the material available, because a clip cannot
      # give more seconds than it has.
      def envelope_cut(clips, out: output_path("envelope_cut"))
        levels = envelope
        bounds = boundaries(levels, segments: clips.length, ceiling: @seconds)
        lengths = bounds.each_cons(2).map { |a, b| (b - a).round(2) }
        raise "the bed is too short for #{clips.length} segments" if lengths.empty?

        Dir.mktmpdir("cut") do |tmp|
          segments = clips.first(lengths.length).each_with_index.map do |clip, index|
            path = File.join(tmp, format("seg_%02d.mp4", index))
            shell([
              "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
              "-i", clip, "-t", lengths[index].to_s,
              "-vf", "scale=#{WIDTH}:#{HEIGHT}:force_original_aspect_ratio=increase," \
                     "crop=#{WIDTH}:#{HEIGHT},fps=#{FPS},setsar=1",
              "-an", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", path
            ])
            path
          end

          total = lengths.sum
          inputs = segments.flat_map { |path| ["-i", path] }
          concat = segments.each_index.map { |i| "[#{i}:v]" }.join + "concat=n=#{segments.length}:v=1:a=0[v]"
          shell([
            "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            *inputs, "-i", @audio,
            "-filter_complex", concat,
            "-map", "[v]", "-map", "#{segments.length}:a",
            "-t", total.to_s, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=out:st=#{total - 1}:d=1",
            "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", "-shortest", out
          ])
          finish("envelope_cut", out, "boundaries" => bounds, "lengths" => lengths,
                                     "segments" => segments.length, "audio" => @audio)
        end
      end

      # Root-mean-square energy of the bed per quarter second, mono at 8 kHz.
      def envelope(rate: 8000, window: 0.25)
        pcm, status = Open3.capture2(Studio::Subprocess.environment,
                                     "ffmpeg", "-nostdin", "-loglevel", "error",
                                     "-i", @audio, "-ac", "1", "-ar", rate.to_s, "-f", "s16le", "-")
        raise "could not read #{@audio}" unless status.success?

        samples = pcm.unpack("s<*")
        size = (rate * window).round
        samples.each_slice(size).map do |slice|
          Math.sqrt(slice.sum { |value| value.to_f**2 } / slice.length)
        end
      end

      # Boundaries on the rises, each gap between a floor and the length of one
      # clip. The floor keeps a segment readable; the ceiling keeps it honest,
      # because a clip cannot give more seconds than it holds.
      def boundaries(levels, rise: 1.35, gap: 4.0, minimum: 3.0, segments: 4, ceiling: 10.0)
        # A floor longer than the ceiling would make every gap unsatisfiable.
        minimum = [minimum, ceiling / 2.0].min
        window = [levels.length * 0.25, segments * ceiling].min
        last = (window / 0.25).floor
        rises = levels.each_cons(2).each_with_index.select { |(a, b), _| b / [a, 1.0].max >= rise }
                      .map { |_, index| index + 1 }
                      .select { |index| index < last }

        picked = []
        rises.each do |index|
          next if picked.any? { |at| (at - index).abs * 0.25 < gap }

          picked << index
        end
        picks = picked.sort.first(segments - 1)
        picks = (1...segments).map { |i| (last * i / segments) } if picks.length < segments - 1

        bounds = [0.0]
        picks.each do |index|
          at = (index * 0.25).round(2)
          at = [at, bounds.last + minimum].max
          at = [at, bounds.last + ceiling].min
          bounds << at.round(2)
        end
        bounds << [window, bounds.last + ceiling].min
        bounds.pop if bounds.length > 2 && (bounds.last - bounds[-2]) < minimum
        bounds
      end

      def extract_frames(clip, tmp, size)
        # The frames must outlive the block, so this directory is removed with
        # the parent temp tree rather than on return.
        dir = Dir.mktmpdir("frames", tmp)
        shell([
          "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
          "-i", clip, "-t", @seconds.to_s, "-vf", "scale=#{size[0]}:#{size[1]},fps=#{FPS}",
          File.join(dir, "f_%05d.png")
        ])
        Dir.glob(File.join(dir, "f_*.png")).sort
      end

      def encode(pattern, out, upscale: false)
        filter = upscale ? "scale=#{WIDTH}:#{HEIGHT}:flags=lanczos" : "null"
        shell([
          "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
          "-framerate", FPS.to_s, "-i", pattern, "-vf", filter,
          "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", out
        ])
      end

      # Depth 0-1 with near bright, at the delivery size, from the local
      # estimator or postpro's cues when the model is absent.
      def depth_plane(image)
        return nil unless defined?(Postpro::Depth)

        plane = Postpro::Depth.near(image)
        return nil unless plane

        plane = plane.resize(WIDTH.to_f / plane.width) if plane.width < WIDTH
        # The estimator returns 0..1 floats, not 0..255 samples. Normalising by
        # its own range keeps the warp correct whichever scale it hands back.
        low = plane.min
        span = plane.max - low
        span = 1.0 if span.abs < 1e-6
        plane.linear(1.0 / span, -low / span).copy(interpretation: :"b-w")
      end

      # Scale and crop to the delivery frame without letterboxing.
      def fitted(image)
        scale = [WIDTH.to_f / image.width, HEIGHT.to_f / image.height].max
        scaled = image.resize(scale)
        scaled.crop((scaled.width - WIDTH) / 2, (scaled.height - HEIGHT) / 2, WIDTH, HEIGHT)
      end

      def vips_image(path)
        Vips::Image.new_from_file(path, access: :sequential)
      end

      def output_path(name, ext: "mp4")
        path = File.join(@directory, "#{@subject}_#{name}.#{ext}")
        raise "refusing to overwrite #{path}" if File.exist?(path)

        path
      end

      # The sidecar is the provenance: what was done, to what, with which
      # numbers, so a piece reproduces from its own record.
      def finish(kind, out, record)
        raise "ffmpeg wrote no #{out}" unless File.file?(out)

        sidecar = "#{out}.json"
        File.write(sidecar, JSON.pretty_generate(
                              "kind" => kind, "subject" => @subject, "output" => out,
                              "size" => [WIDTH, HEIGHT], "fps" => FPS, "seconds" => @seconds,
                              "created_at" => Time.now.utc.iso8601, **record
                            ))
        File.chmod(0o600, sidecar)
        out
      end

      def shell(argv)
        _, status = Open3.capture2e(Studio::Subprocess.environment, *argv)
        raise "command failed: #{argv.first(4).join(" ")}" unless status.success?

        status
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  subject = ARGV.first || "ragnhild"
  puts JSON.pretty_generate(Studio::Visual::Apparatus.new(subject:).run)
end
