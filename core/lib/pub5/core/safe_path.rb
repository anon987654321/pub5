# frozen_string_literal: true
require "pathname"
require_relative "errors"

module Pub5
  module Core
    class SafePath
      def initialize(root)
        @root = File.realpath(root)
      end

      def resolve(path)
        raw = path.to_s
        raise Denied, "absolute paths are not capabilities" if Pathname.new(raw).absolute?
        parts = raw.split(/[\\\/]/)
        raise Denied, "parent traversal is forbidden" if parts.include?("..")
        clean = Pathname.new(raw).cleanpath.to_s
        raise Denied, "empty path" if clean.empty? || clean == "."
        candidate = File.expand_path(clean, @root)
        prefix = "#{@root}#{File::SEPARATOR}"
        raise Denied, "path escapes the world" unless candidate.start_with?(prefix)

        cursor = @root
        clean.split("/").each do |part|
          cursor = File.join(cursor, part)
          raise Denied, "symlink traversal is forbidden: #{part}" if File.symlink?(cursor)
        end
        candidate
      end

      def relative(path)
        resolve(path).delete_prefix("#{@root}/")
      end
    end
  end
end
