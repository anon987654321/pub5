#!/usr/bin/env ruby
# frozen_string_literal: true

# promo — turn a set of portrait stills into one vertical motion-graphics clip
# with a soundtrack. This is the assembly step the selfie pipeline hands to:
# generate stills, then cut them into the piece the subject actually watches.
#
# The motion is a slow push (Ken Burns) on each still, a crossfade between
# stills, one film look over the whole piece and the dilla render underneath.
# It composes ffmpeg directly rather than going through Postpro's per-frame
# in-process grade, which is the right tool for a shot clip but measured over
# three minutes for a four-second 1080p clip.
#
#   ruby STUDIO/promo.rb --subject merethe --audio dilla.wav --out merethe.mp4
#   ruby STUDIO/promo.rb --still a.jpg --still b.jpg --preset dilla_heavy --out cut.mp4
#   ruby STUDIO/promo.rb api '{"action":"plan","stills":["a.jpg"]}'
#
# A render writes <name>.mp4 plus a .promo.json sidecar naming every input, the
# look, the timings and the ffmpeg argv, so the cut reproduces from its inputs.

require "json"
require "optparse"
require "fileutils"
require "open3"
require "time"
require "yaml"
require_relative "api"
require_relative "output_paths"

module Studio
  module Promo
    IMAGE_EXTENSIONS = %w[jpg jpeg png webp].freeze
    DEFAULT_SIZE = [1080, 1920].freeze
    DEFAULT_FPS = 30
    DEFAULT_STILL_SECONDS = 4.5
    DEFAULT_CROSSFADE = 1.0
    LOUDNESS_TARGET = -14.0

    # The video-grade catalogue is the one authority for looks shared by
    # Promo, Postpro and Dilla. A missing or malformed catalogue is a defect,
    # not a reason to silently render with a second, stale table.
    module_function

    def looks
      path = File.join(__dir__, "postpro", "video.yml")
      raise ArgumentError, "video grade catalogue is missing: #{path}" unless File.file?(path)

      parse_video_presets(File.read(path, encoding: "UTF-8"))
    end

    def parse_video_presets(text)
      document = YAML.safe_load(
        text, permitted_classes: [], permitted_symbols: [], aliases: false
      )
      raise ArgumentError, "video grade catalogue must be a mapping" unless document.is_a?(Hash)
      raise ArgumentError, "unsupported video grade schema" unless document["schema"] == "postpro.video.v1"

      presets = document["presets"]
      raise ArgumentError, "video grade catalogue needs a presets mapping" unless presets.is_a?(Hash) && !presets.empty?

      presets.each_with_object({}) do |(name, spec), result|
        unless name.is_a?(String) && name.match?(/\A[a-z0-9_]+\z/) && spec.is_a?(Hash)
          raise ArgumentError, "invalid video preset entry: #{name.inspect}"
        end

        filters = spec["filters"]
        unless filters.is_a?(Array) && filters.all? { |filter| filter.is_a?(String) && !filter.strip.empty? }
          raise ArgumentError, "video preset #{name.inspect} needs a list of non-empty filter strings"
        end

        result[name] = filters.freeze
      end.freeze
    rescue Psych::Exception => error
      raise ArgumentError, "video grade catalogue is invalid: #{error.message}"
    end

    # The ffmpeg argument vector for one cut. Pure: no filesystem writes, so a
    # test can assert the whole graph without rendering.
    def build_args(stills:, audio:, out:, size: DEFAULT_SIZE, fps: DEFAULT_FPS,
                   still_seconds: DEFAULT_STILL_SECONDS, crossfade: DEFAULT_CROSSFADE,
                   look: "dilla_heavy")
      raise ArgumentError, "promo needs at least one still" if stills.empty?
      raise ArgumentError, "promo needs an audio track" if audio.to_s.empty?

      width, height = size
      filters = []
      labels = []

      stills.each_with_index do |_path, index|
        zoom = if index.even?
                 "min(zoom+0.0006,1.14)"
               else
                 "if(lte(zoom,1.0),1.14,max(1.001,zoom-0.0006))"
               end
        chain = [
          "scale=#{width * 2}:#{height * 2}:force_original_aspect_ratio=increase",
          "crop=#{width * 2}:#{height * 2}",
          "zoompan=z='#{zoom}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'" \
          ":d=1:s=#{width}x#{height}:fps=#{fps}",
          "setsar=1",
        ]
        chain.concat(Array(look_filters(look)))
        filters << "[#{index}:v]#{chain.join(',')}[v#{index}]"
        labels << "v#{index}"
      end

      current = labels.first
      offsets = crossfade_offsets(stills.length, still_seconds, crossfade)
      labels.drop(1).each_with_index do |label, index|
        out_label = "x#{index}"
        filters << "[#{current}][#{label}]xfade=transition=fade" \
                   ":duration=#{format_num(crossfade)}:offset=#{format_num(offsets[index])}[#{out_label}]"
        current = out_label
      end

      audio_index = stills.length
      filters << "[#{audio_index}:a]loudnorm=I=#{format_num(LOUDNESS_TARGET)}:TP=-1.5:LRA=11[aout]"

      inputs = stills.flat_map do |path|
        ["-loop", "1", "-framerate", fps.to_s, "-t", format_num(still_seconds), "-i", path]
      end

      [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        *inputs,
        "-i", audio,
        "-filter_complex", filters.join(";"),
        "-map", "[#{current}]", "-map", "[aout]",
        "-c:v", "libx264", "-preset", "medium", "-crf", "18",
        "-pix_fmt", "yuv420p", "-r", fps.to_s,
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart", "-shortest",
        out,
      ]
    end

    def look_filters(name)
      looks.fetch(name.to_s) do
        raise ArgumentError, "unknown look #{name.inspect}; known: #{looks.keys.sort.join(', ')}"
      end
    end

    # How long the piece runs before audio trims it, so a caller can match the
    # still count to the track.
    def total_seconds(still_count, still_seconds: DEFAULT_STILL_SECONDS, crossfade: DEFAULT_CROSSFADE)
      return 0.0 if still_count <= 0

      (still_count * still_seconds) - ((still_count - 1) * crossfade)
    end

    def crossfade_offsets(still_count, still_seconds, crossfade)
      return [] if still_count < 2

      # Each still runs `still_seconds`, and a crossfade overlaps `crossfade`
      # of the previous still, so the k-th transition starts at
      # k * (still_seconds - crossfade) on the running stream.
      step = still_seconds - crossfade
      (1...(still_count)).map { |index| index * step }
    end

    def format_num(value)
      number = value.to_f
      number == number.to_i ? number.to_i.to_s : format("%.3f", number).sub(/0+\z/, "").sub(/\.\z/, "")
    end

    def stills_for_subject(subject, root: nil)
      base = File.expand_path(root || File.join(__dir__, "lora"))
      directory = File.join(base, subject.to_s)
      raise ArgumentError, "no subject directory for #{subject.inspect}" unless File.directory?(directory)

      Dir.glob(File.join(directory, "#{subject}_selfie_*")).sort.select do |path|
        IMAGE_EXTENSIONS.include?(File.extname(path).delete(".").downcase) && File.file?(path)
      end
    end

    def ffmpeg?
      @ffmpeg_checked ||= begin
        _, status = Open3.capture2e("ffmpeg", "-version")
        status.success?
      rescue Errno::ENOENT
        false
      end
    end

    def render(stills:, audio:, out:, look: "dilla_heavy", size: DEFAULT_SIZE,
               fps: DEFAULT_FPS, still_seconds: DEFAULT_STILL_SECONDS,
               crossfade: DEFAULT_CROSSFADE)
      raise "ffmpeg is not on PATH" unless ffmpeg?
      raise ArgumentError, "audio not found: #{audio}" unless File.file?(audio)

      FileUtils.mkdir_p(File.dirname(File.expand_path(out)))
      args = build_args(stills:, audio:, out:, size:, fps:, still_seconds:, crossfade:, look:)
      _, status = Open3.capture2e(*args)
      raise "ffmpeg failed to write #{out}" unless status.success? && File.file?(out)

      write_sidecar(out, stills:, audio:, look:, size:, fps:, still_seconds:, crossfade:, args:)
      out
    end

    def write_sidecar(out, stills:, audio:, look:, size:, fps:, still_seconds:, crossfade:, args:)
      path = out.sub(/\.mp4\z/, "") + ".promo.json"
      report = {
        "engine" => "promo",
        "created_at" => Time.now.utc.iso8601,
        "look" => look,
        "size" => size,
        "fps" => fps,
        "still_seconds" => still_seconds,
        "crossfade_seconds" => crossfade,
        "still_count" => stills.length,
        "duration_seconds" => total_seconds(stills.length, still_seconds:, crossfade:),
        "stills" => stills,
        "audio" => audio,
        "output" => out,
        "ffmpeg_argv" => args,
      }
      File.write(path, JSON.pretty_generate(report) + "\n")
      path
    end

    module CLI
      module_function

      def run(argv)
        return Studio::Api.respond(api_actions, argv:) if Studio::Api.requested?(argv)

        options = { stills: [], size: DEFAULT_SIZE, fps: DEFAULT_FPS,
                    still_seconds: DEFAULT_STILL_SECONDS, crossfade: DEFAULT_CROSSFADE,
                    look: "dilla_heavy" }
        parser = OptionParser.new do |opts|
          opts.banner = "usage: ruby STUDIO/promo.rb --still FILE... --audio TRACK --out FILE.mp4"
          opts.on("--still FILE", "a still to include (repeatable)") { |value| options[:stills] << value }
          opts.on("--subject NAME", "take the subject's selfie stills under STUDIO/lora") { |value| options[:subject] = value }
          opts.on("--audio FILE", "soundtrack (dilla.wav and friends)") { |value| options[:audio] = value }
          opts.on("--out FILE", "write the MP4 here") { |value| options[:out] = value }
          opts.on("--look NAME", "film look from video.yml (default dilla_heavy)") { |value| options[:look] = value }
          opts.on("--seconds N", Float, "seconds per still (default #{DEFAULT_STILL_SECONDS})") { |value| options[:still_seconds] = value }
          opts.on("--crossfade N", Float, "crossfade seconds (default #{DEFAULT_CROSSFADE})") { |value| options[:crossfade] = value }
          opts.on("--size WxH", "frame size (default #{DEFAULT_SIZE.join('x')})") do |value|
            width, height = value.split("x").map(&:to_i)
            options[:size] = [width, height]
          end
          opts.on("--fps N", Integer, "frames per second (default #{DEFAULT_FPS})") { |value| options[:fps] = value }
          opts.on("--looks", "list the available looks and exit") { options[:list_looks] = true }
          opts.on("-h", "--help") { puts opts; exit 0 }
        end
        parser.parse!(argv)

        if options[:list_looks]
          puts Studio::Promo.looks.keys.sort
          exit 0
        end

        options[:stills] = Studio::Promo.stills_for_subject(options[:subject]) if options[:subject]
        abort "promo: no stills (use --still or --subject)" if options[:stills].empty?
        abort "promo: --audio is required" unless options[:audio]
        abort "promo: --out is required" unless options[:out]

        out = Studio::Promo.render(**options.reject { |key, _| key == :list_looks || key == :subject })
        puts "promo: #{out} (#{format('%.1f', Studio::Promo.total_seconds(options[:stills].length, still_seconds: options[:still_seconds], crossfade: options[:crossfade]))}s, #{options[:stills].length} stills)"
      end

      def api_actions
        {
          "looks" => ->(_request) { Studio::Promo.looks.keys.sort },
          "plan" => ->(request) { plan(request) },
        }
      end

      def plan(request)
        stills = Array(request["stills"]).map(&:to_s)
        stills = Studio::Promo.stills_for_subject(request["subject"]) if stills.empty? && request["subject"]
        {
          "look" => request.fetch("look", "dilla_heavy"),
          "still_count" => stills.length,
          "stills" => stills,
          "duration_seconds" => Studio::Promo.total_seconds(stills.length),
          "looks" => Studio::Promo.looks.keys.sort,
        }
      end
    end
  end
end

Studio::Promo::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
