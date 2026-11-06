# frozen_string_literal: true

require "fileutils"
require "securerandom"

module Core
  # The one atomic write. A reader sees the old bytes or the new bytes, never
  # half of either: write a temp file in the same directory, fsync it, rename
  # it over the destination, fsync the directory.
  module Atomic
    module_function

    def write(path, content, mode: nil)
      path = File.expand_path(path)
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir)
      refuse_shape!(path, dir)
      mode ||= File.exist?(path) ? File.stat(path).mode & 0o7777 : 0o644
      temp = File.join(dir, ".#{File.basename(path)}.#{SecureRandom.hex(6)}.tmp")
      File.open(temp, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, mode) do |io|
        io.write(content)
        io.flush
        io.fsync
      end
      File.rename(temp, path)
      fsync_dir(dir)
      path
    ensure
      File.unlink(temp) if temp && File.exist?(temp)
    end

    # Writing through a symlink or onto a hard-linked file would change bytes
    # somewhere the caller never named.
    def refuse_shape!(path, dir)
      raise Refusal.new(:write, path, "parent is a symlink") if File.symlink?(dir)
      return unless File.exist?(path) || File.symlink?(path)

      stat = File.lstat(path)
      raise Refusal.new(:write, path, "destination is a symlink") if stat.symlink?
      raise Refusal.new(:write, path, "destination is not a regular file") unless stat.file?
      raise Refusal.new(:write, path, "destination has #{stat.nlink} hard links") if stat.nlink > 1
    end

    def fsync_dir(dir)
      File.open(dir, File::RDONLY) { |io| io.fsync }
    rescue Errno::EINVAL, Errno::EBADF
      nil # some filesystems cannot fsync a directory; the rename is still atomic
    end
  end
end
