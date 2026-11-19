#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "rbconfig"
require "securerandom"
require "time"
require "tempfile"
require_relative "../output_paths"
require_relative "../subprocess"
require_relative "consent"
require_relative "selfie_series"

module Studio
  module Lora
    # Turns a complete, consent-authorised selfie sitting into one private film.
    # The stills use the existing heavy Postpro path; the assembled film then
    # receives one coherent house-stock motion grade and a Dilla music bed.
    class SelfieFilm
      SUBJECTS = %w[johann ragnhild merethe].freeze
      DEFAULT_COUNT = 10
      MAX_COUNT = 12
      WIDTH = 720
      HEIGHT = 1280
      FPS = 24
      STILL_SECONDS = 3.0
      TRANSITION_SECONDS = 0.5
      DILLA_SEED = 261_013
      POSTPRO_PRESET = "house"

      class Error < StandardError; end

      def initialize(output_root: nil, studio_root: File.expand_path("..", __dir__))
        @studio_root = File.expand_path(studio_root)
        @output_root = File.expand_path(
          output_root || File.join(Studio::OutputPaths.render_directory, "selfie-films")
        )
        if Studio::OutputPaths.inside_repository?(@output_root)
          raise Error, "selfie films must stay outside the Git checkout"
        end
      end

      def run_all(subjects: SUBJECTS, count: DEFAULT_COUNT, engine: nil)
        names = validate_subjects(subjects)
        total = Integer(count)
        raise ArgumentError, "count must be between 1 and #{MAX_COUNT}" unless total.between?(1, MAX_COUNT)

        checks = names.map do |subject|
          authorize!(subject)
          { "subject" => subject, "state" => "READY" }
        rescue StandardError => error
          { "subject" => subject, "state" => "BLOCKED", "reason" => concise(error) }
        end
        ready = checks.select { |item| item["state"] == "READY" }.map { |item| item["subject"] }
        return { "state" => "BLOCKED", "subjects" => checks, "reason" => "no subject passed consent and source-rights preflight" } if ready.empty?

        secure_directory!(@output_root)
        session = File.join(@output_root, "#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}-#{SecureRandom.hex(3)}")
        secure_directory!(session)

        audio = File.join(session, "dilla.wav")
        begin
          render_dilla!(audio)
        rescue StandardError => error
          return {
            "state" => "DELIVERY_FAILED", "session" => session, "subjects" => checks,
            "reason" => "Dilla soundtrack failed: #{concise(error)}"
          }
        end

        results = ready.map do |subject|
          begin
            build_subject_film!(subject, session:, audio:, count: total, engine:)
          rescue StandardError => error
            { "subject" => subject, "state" => "DELIVERY_FAILED", "reason" => concise(error) }
          end
        end
        blocked = checks.reject { |item| item["state"] == "READY" }
        results.concat(blocked)
        state = results.all? { |item| item["state"] == "PASS" } ? "PASS" : "PARTIAL"
        { "state" => state, "session" => session, "soundtrack" => audio, "subjects" => results,
          "git_publication" => "NOT_PERFORMED: identity media remain in private local storage" }
      rescue ArgumentError, TypeError => error
        { "state" => "BLOCKED", "reason" => concise(error) }
      end

      def self.expected_duration(image_count)
        count = Integer(image_count)
        raise ArgumentError, "at least one still is required" unless count.positive?

        count * STILL_SECONDS - (count - 1) * TRANSITION_SECONDS
      end

      def self.montage_graph(image_count)
        count = Integer(image_count)
        raise ArgumentError, "image count must be between 1 and #{MAX_COUNT}" unless count.between?(1, MAX_COUNT)

        filters = count.times.map do |index|
          drift = index.even? ? "0.38" : "0.62"
          "[#{index}:v]scale=#{WIDTH}:#{HEIGHT}:force_original_aspect_ratio=increase," \
            "crop=#{WIDTH}:#{HEIGHT}," \
            "zoompan=z='min(zoom+0.00055,1.04)':x='(iw-iw/zoom)*#{drift}':" \
            "y='(ih-ih/zoom)*0.50':d=1:s=#{WIDTH}x#{HEIGHT}:fps=#{FPS}," \
            "setsar=1,format=yuv420p,settb=expr=1/#{FPS},setpts=PTS-STARTPTS[v#{index}]"
        end
        current = "v0"
        (1...count).each do |index|
          next_label = "x#{index}"
          offset = (index * (STILL_SECONDS - TRANSITION_SECONDS)).round(6)
          filters << "[#{current}][v#{index}]xfade=transition=fade:" \
                     "duration=#{TRANSITION_SECONDS}:offset=#{offset}[#{next_label}]"
          current = next_label
        end
        filters << "[#{current}]format=yuv420p[vout]"
        filters.join(";")
      end

      def self.audio_filter(duration)
        seconds = Float(duration)
        raise ArgumentError, "film duration must exceed 2.5 seconds" unless seconds.finite? && seconds > 2.5

        fade_out = (seconds - 1.6).round(3)
        "loudnorm=I=-16:TP=-1.5:LRA=11," \
          "afade=t=in:st=0:d=0.65," \
          "afade=t=out:st=#{fade_out}:d=1.6"
      end

      private

      def validate_subjects(subjects)
        names = Array(subjects).map(&:to_s)
        raise ArgumentError, "name at least one subject" if names.empty?
        raise ArgumentError, "duplicate subjects are not allowed" unless names.uniq.length == names.length
        invalid = names.reject { |name| SUBJECTS.include?(name) }
        raise ArgumentError, "unsupported subject name(s): #{invalid.join(", ")}" unless invalid.empty?

        names
      end

      def authorize!(subject)
        directory = File.join(Studio::Visual::IdeaPicture::SUBJECTS, subject)
        Consent.require!(subject:, subject_directory: directory, action: :generation)
      end

      def build_subject_film!(subject, session:, audio:, count:, engine:)
        subject_root = File.join(session, subject)
        stills_root = File.join(subject_root, "stills")
        secure_directory!(subject_root)
        secure_directory!(stills_root)

        series = Studio::Visual::SelfieSeries.new(
          subject:, directory: stills_root, engine:,
          ledger_path: File.join(subject_root, "ledger.jsonl")
        )
        stills = series.run(count:, replace: false)
        unless stills.length == count
          raise Error, "only #{stills.length}/#{count} stills rendered; refusing to assemble an incomplete film"
        end
        stills.each { |path| validate_private_file!(path) }

        montage = File.join(subject_root, "#{subject}_montage.mp4")
        graded = File.join(subject_root, "#{subject}_house_grade.mp4")
        final = File.join(subject_root, "#{subject}_selfies.mp4")
        make_montage!(stills, montage)
        grade_film!(montage, graded, subject:)
        mux_dilla!(graded, audio, final)
        video = probe_video!(final)
        still_records = stills.map do |path|
          { "file" => File.basename(path), "sha256" => Digest::SHA256.file(path).hexdigest }
        end
        manifest = {
          "schema" => "studio.selfie_film.v1", "subject" => subject,
          "created_at" => Time.now.utc.iso8601, "still_count" => stills.length,
          "stills" => still_records,
          "soundtrack" => { "file" => File.basename(audio), "sha256" => Digest::SHA256.file(audio).hexdigest,
                            "renderer" => "STUDIO/dilla/dilla.rb", "seed" => DILLA_SEED },
          "postpro" => { "entrypoint" => "STUDIO/postpro/postpro.rb", "preset" => POSTPRO_PRESET,
                         "grade_sidecar" => File.basename("#{graded}.json") },
          "video" => video.merge("file" => File.basename(final), "sha256" => Digest::SHA256.file(final).hexdigest),
          "privacy" => { "directory_mode" => "0700", "file_mode" => "0600",
                         "inside_repository" => false, "git_publication" => false }
        }
        write_private_json(File.join(subject_root, "manifest.json"), manifest)
        { "subject" => subject, "state" => "PASS", "film" => final,
          "manifest" => File.join(subject_root, "manifest.json"), "duration_seconds" => video.fetch("duration_seconds") }
      end

      def render_dilla!(audio)
        dilla = File.join(@studio_root, "dilla", "dilla.rb")
        raise Error, "Dilla engine is missing: #{dilla}" unless File.file?(dilla)
        run!({}, RbConfig.ruby, dilla, "--showcase", "--no-video", "--out", audio,
             "--seed", DILLA_SEED.to_s, timeout: 900)
        raise Error, "Dilla did not produce a non-empty WAV" unless File.file?(audio) && File.size(audio).positive?

        File.chmod(0o600, audio)
        Dir.glob(File.join(File.dirname(audio), "dilla.*")).each do |path|
          File.chmod(0o600, path) if File.file?(path) && !File.symlink?(path)
        end
      end

      def make_montage!(stills, output)
        require_tools!("ffmpeg")
        args = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-filter_complex_threads", "1"]
        stills.each { |path| args.concat(["-loop", "1", "-framerate", FPS.to_s, "-t", STILL_SECONDS.to_s, "-i", path]) }
        args.concat([
          "-filter_complex", self.class.montage_graph(stills.length), "-map", "[vout]",
          "-an", "-r", FPS.to_s, "-c:v", "libx264", "-preset", "medium", "-crf", "17",
          "-pix_fmt", "yuv420p", "-movflags", "+faststart", output
        ])
        run!({}, *args, timeout: 600)
        validate_private_file!(output)
      end

      def grade_film!(input, output, subject:)
        script = File.join(@studio_root, "postpro", "postpro.rb")
        seed = Digest::SHA256.hexdigest("postpro-selfie-film:#{subject}:#{DILLA_SEED}")[0, 8].to_i(16)
        frames = (self.class.expected_duration(DEFAULT_COUNT) * FPS).ceil
        pixels = WIDTH * HEIGHT * frames + 1_000_000
        env = {
          "POSTPRO_SEED" => seed.to_s,
          "POSTPRO_VIDEO_MAX_FRAMES" => (frames + 4).to_s,
          "POSTPRO_VIDEO_MAX_PIXELS" => pixels.to_s,
          "POSTPRO_VIDEO_MAX_SECONDS" => (frames + 100).to_s,
          "POSTPRO_VIDEO_MAX_TEMP_BYTES" => "2000000000"
        }
        run!(env, RbConfig.ruby, script, "--video", input, "--output", output,
             "--preset", POSTPRO_PRESET, timeout: frames + 180)
        validate_private_file!(output)
        sidecar = "#{output}.json"
        raise Error, "Postpro did not write its grade receipt" unless File.file?(sidecar) && !File.symlink?(sidecar)
        File.chmod(0o600, sidecar)
      end

      def mux_dilla!(video, audio, output)
        duration = self.class.expected_duration(DEFAULT_COUNT)
        run!({}, "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
             "-i", video, "-i", audio, "-map", "0:v:0", "-map", "1:a:0",
             "-af", self.class.audio_filter(duration), "-c:v", "copy",
             "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
             "-t", format("%.6f", duration), "-shortest", "-map_metadata", "-1",
             "-movflags", "+faststart", output, timeout: 300)
        validate_private_file!(output)
      end

      def probe_video!(path)
        require_tools!("ffprobe")
        raw = run!({}, "ffprobe", "-v", "error", "-show_streams", "-show_format",
                   "-of", "json", path, timeout: 30)
        data = JSON.parse(raw)
        streams = data.fetch("streams")
        video = streams.find { |stream| stream["codec_type"] == "video" }
        audio = streams.find { |stream| stream["codec_type"] == "audio" }
        raise Error, "finished film is missing its video or Dilla audio stream" unless video && audio
        raise Error, "finished film has unexpected dimensions" unless video["width"].to_i == WIDTH && video["height"].to_i == HEIGHT
        raise Error, "finished film is not H.264/AAC" unless video["codec_name"] == "h264" && audio["codec_name"] == "aac"

        duration = data.dig("format", "duration").to_f
        expected = self.class.expected_duration(DEFAULT_COUNT)
        raise Error, "finished film duration differs from its edit" if (duration - expected).abs > 0.35
        { "width" => WIDTH, "height" => HEIGHT, "frame_rate" => "#{FPS}/1",
          "video_codec" => video["codec_name"], "audio_codec" => audio["codec_name"],
          "duration_seconds" => duration.round(3) }
      rescue JSON::ParserError, KeyError => error
        raise Error, "ffprobe returned an invalid delivery report: #{error.message}"
      end

      def run!(env, *args, timeout:)
        stdout, stderr, status = Studio::Subprocess.capture3(
          env, *args, timeout:, chdir: @studio_root
        )
        return stdout if status.success?

        detail = [stderr, stdout].compact.join("\n").lines.last(5).join(" ").strip
        raise Error, "#{File.basename(args.first)} failed (#{status.exitstatus}): #{detail}"
      end

      def require_tools!(*names)
        missing = names.reject { |name| executable?(name) }
        raise Error, "required media tools are missing from PATH: #{missing.join(", ")}" unless missing.empty?
      end

      def executable?(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
          candidate = File.join(directory, name)
          File.file?(candidate) && File.executable?(candidate)
        end
      end

      def validate_private_file!(path)
        raise Error, "media file is missing or a symlink: #{path}" unless File.file?(path) && !File.symlink?(path)
        stat = File.lstat(path)
        raise Error, "media file is not owned by the current user: #{path}" unless stat.uid == Process.uid
        raise Error, "media file must be singly-linked and owner-only: #{path}" unless stat.nlink == 1 && (stat.mode & 0o077).zero?
        raise Error, "media file is empty: #{path}" unless stat.size.positive?

        true
      end

      def secure_directory!(path)
        raise Error, "refusing symlinked media directory: #{path}" if File.symlink?(path)
        FileUtils.mkdir_p(path, mode: 0o700)
        stat = File.lstat(path)
        raise Error, "media directory is not a directory owned by the current user: #{path}" unless stat.directory? && stat.uid == Process.uid
        File.chmod(0o700, path)
        true
      end

      def write_private_json(path, document)
        raise Error, "refusing to replace existing manifest: #{path}" if File.exist?(path) || File.symlink?(path)
        Tempfile.create([".selfie-film-", ".json"], File.dirname(path)) do |file|
          file.write(JSON.pretty_generate(document))
          file.write("\n")
          file.flush
          file.fsync
          file.chmod(0o600)
          File.rename(file.path, path)
        end
        File.chmod(0o600, path)
      end

      def concise(error)
        "#{error.class}: #{error.message.to_s.lines.first.to_s.strip[0, 240]}"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { subjects: Studio::Lora::SelfieFilm::SUBJECTS, count: Studio::Lora::SelfieFilm::DEFAULT_COUNT }
  OptionParser.new do |parser|
    parser.banner = "usage: ruby STUDIO/lora/selfie_film.rb [--all | --subject NAME] [--count N] [--engine MODEL]"
    parser.on("--all", "render all three authorised subjects (default)") { options[:subjects] = Studio::Lora::SelfieFilm::SUBJECTS }
    parser.on("--subject NAME", "render one named subject") { |value| options[:subjects] = [value] }
    parser.on("--count N", Integer, "number of stills per subject (1..12; default 10)") { |value| options[:count] = value }
    parser.on("--engine MODEL", "optional configured Replicate still engine") { |value| options[:engine] = value }
    parser.on("-h", "--help", "show this help") { puts parser; exit 0 }
  end.parse!
  report = Studio::Lora::SelfieFilm.new.run_all(**options)
  puts JSON.pretty_generate(report)
  exit(report["state"] == "PASS" ? 0 : 1)
end
