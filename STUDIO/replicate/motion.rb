# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "subprocess"

module Studio
  class ReplicateClient
    # Continuity between clips. A piece cut from three separate predictions
    # looks like three separate predictions unless each one starts where the
    # last one ended, so the final frame of a clip becomes the first frame of
    # the next.
    module Motion
      module_function

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
