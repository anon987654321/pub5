# frozen_string_literal: true
require "fileutils"
require_relative "errors"
require_relative "safe_path"

module Pub5
  module Core
    class AtomicWriter
      DEFAULT_PROTECTED = %w[registry/** laws/** core/** db/migrate/** config/credentials.yml.enc].freeze

      def initialize(root:, capabilities:, protected_paths: DEFAULT_PROTECTED)
        @root = File.realpath(root)
        @paths = SafePath.new(@root)
        @capabilities = capabilities
        @protected_paths = protected_paths
      end

      def write(path, bytes, mode: 0o600)
        @capabilities.allow!("write", path: path)
        relative = path.to_s
        if @protected_paths.any? { |pattern| File.fnmatch?(pattern, relative, File::FNM_PATHNAME) }
          raise Denied, "protected path requires an operator transaction: #{relative}"
        end
        target = @paths.resolve(relative)
        ensure_parent(target)
        temp = File.join(File.dirname(target), ".#{File.basename(target)}.#{Process.pid}.tmp")
        begin
          File.open(temp, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
            file.binmode
            file.write(bytes)
            file.flush
            file.fsync
          end
          raise Denied, "target became a symlink" if File.symlink?(target)
          File.rename(temp, target)
          File.open(File.dirname(target)) { |directory| directory.fsync }
        ensure
          File.unlink(temp) if File.exist?(temp)
        end
        target
      end

      private

      def ensure_parent(target)
        relative = File.dirname(target).delete_prefix("#{@root}/")
        cursor = @root
        relative.split("/").each do |part|
          next if part == "."
          cursor = File.join(cursor, part)
          raise Denied, "symlink parent is forbidden" if File.symlink?(cursor)
          Dir.mkdir(cursor, 0o700) unless Dir.exist?(cursor)
        end
      end
    end
  end
end
