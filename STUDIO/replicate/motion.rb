# frozen_string_literal: true

require "fileutils"
require "open3"
require "json"
require "digest"
require_relative "subprocess"

module Studio
  class ReplicateClient
    # Continuity between clips. A piece cut from three separate predictions
    # looks like three separate predictions unless each one starts where the
    # last one ended, so the final frame of a clip becomes the first frame of
    # the next.
    module Motion
      module_function

      # Sample distinct temporal moments without another provider prediction.
      # These are candidates, never automatically approved photographs.
      def sample_frames(clip, directory:, count: 8)
        count = Integer(count)
        raise ArgumentError, "count must be 2..24" unless count.between?(2, 24)
        clip = File.expand_path(clip)
        raise ArgumentError, "clip must be a local regular file" unless File.file?(clip) && !File.symlink?(clip)
        directory = File.expand_path(directory)
        raise ArgumentError, "output directory must not exist" if File.exist?(directory) || File.symlink?(directory)

        stdout, _, status = Studio::Subprocess.capture3(
          "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
          "format=duration", "-of", "json", clip, timeout: 30
        )
        raise "could not probe clip" unless status.success?
        duration = Float(JSON.parse(stdout).fetch("format").fetch("duration"))
        raise "invalid clip duration" unless duration.finite? && duration.positive? && duration <= 3600

        Dir.mkdir(directory, 0o700)
        source_sha = Digest::SHA256.file(clip).hexdigest
        frames = count.times.map do |index|
          seconds = duration * (index + 0.5) / count
          path = File.join(directory, format("frame_%02d.png", index + 1))
          _, _, status = Studio::Subprocess.capture3(
            "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
            "-ss", format("%.6f", seconds), "-i", clip, "-map", "0:v:0",
            "-frames:v", "1", path, timeout: 60
          )
          raise "could not extract frame #{index + 1}" unless status.success? && File.file?(path) && File.size?(path)
          File.chmod(0o600, path)
          { "path" => path, "requested_seconds" => seconds, "sha256" => Digest::SHA256.file(path).hexdigest }
        end
        receipt = { "source_sha256" => source_sha, "duration" => duration,
                    "frames" => frames, "review" => "NOT_REVIEWED", "provider_calls" => 0 }
        File.open(File.join(directory, "frames.json"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.pretty_generate(receipt))
        end
        receipt
      end

      def last_frame(clip, out:)
        raise ArgumentError, "clip not found: #{clip}" unless File.file?(clip)

        FileUtils.mkdir_p(File.dirname(File.expand_path(out)))
        # Seek just short of the end: seeking to the exact duration lands past
        # the last decodable frame on some encoders and writes nothing.
        args = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-sseof", "-0.2", "-i", clip.to_s, "-frames:v", "1", "-q:v", "2", out.to_s]
        _, status = Open3.capture2e(Studio::Subprocess.environment, *args)
        raise "could not read the last frame of #{clip}" unless status.success? && File.file?(out)

        File.chmod(0o600, out)
        out
      end
    end
  end
end
