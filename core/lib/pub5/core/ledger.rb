# frozen_string_literal: true
require "json"
require "time"
require "fileutils"

module Pub5
  module Core
    class Ledger
      MAX_EVENT_BYTES = 16_384

      def initialize(path)
        @path = path
      end

      def append(event)
        raise ArgumentError, "ledger event must be a mapping" unless event.is_a?(Hash)
        line = JSON.generate(event.merge("at" => Time.now.utc.iso8601))
        raise ArgumentError, "ledger event exceeds #{MAX_EVENT_BYTES} bytes" if line.bytesize > MAX_EVENT_BYTES
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
          file.flock(File::LOCK_EX)
          file.write(line)
          file.write("\n")
          file.flush
          file.fsync
        ensure
          file.flock(File::LOCK_UN)
        end
      end
    end
  end
end
