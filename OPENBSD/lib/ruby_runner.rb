# frozen_string_literal: true

require "open3"
require_relative "environment"

module Deploy
  module RubyRunner
    module_function

    def ruby_cmd(root: Environment.repo_root)
      explicit = ENV["PUB5_RUBY"].to_s
      explicit = ENV["PUB4_RUBY"].to_s if explicit.empty?
      unless explicit.empty?
        return explicit if File.executable?(explicit) && compatible_ruby?(explicit)

        raise "configured Ruby is unavailable or older than #{Environment::SUPPORTED_RUBY_MIN}: #{explicit}"
      end
      return RbConfig.ruby if Environment.ruby_version_ok?

      path = openbsd_path("ruby", root:)
      return path if path && compatible_ruby?(path)

      path = command_path("ruby")
      return path if !path.empty? && compatible_ruby?(path)

      raise(Environment.ruby_mismatch_message || "no compatible Ruby found")
    end

    def bundle_cmd(root: Environment.repo_root)
      explicit = ENV["PUB5_BUNDLE"].to_s
      explicit = ENV["PUB4_BUNDLE"].to_s if explicit.empty?
      return explicit if !explicit.empty? && File.executable?(explicit)

      ruby = ruby_cmd(root:)
      suffix = File.basename(ruby).delete_prefix("ruby")
      adjacent = File.join(File.dirname(ruby), "bundle#{suffix}")
      return adjacent if File.executable?(adjacent)

      if !suffix.empty?
        path = openbsd_path("bundle#{suffix}", root:)
        return path if path

        raise "Bundler for selected Ruby package #{File.basename(ruby)} is unavailable"
      end

      path = openbsd_path("bundle", root:)
      return path if path

      command_path("bundle").then { |value| value.empty? ? "bundle" : value }
    end

    # Alternate package names are a fallback. The interpreter already running
    # MASTER wins whenever it meets the compatibility floor.
    def openbsd_path(name, root: Environment.repo_root)
      return unless RUBY_PLATFORM.match?(/openbsd/)

      prefix = name == "ruby" ? "ruby" : "bundle"
      candidates = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).flat_map do |directory|
        next [] unless File.directory?(directory)

        Dir.children(directory).filter_map do |entry|
          next unless entry.match?(/\A#{Regexp.escape(prefix)}(?:[0-9]+(?:\.[0-9]+)*)?\z/)

          path = File.join(directory, entry)
          path if File.file?(path) && File.executable?(path)
        end
      rescue SystemCallError
        []
      end
      candidates.uniq.each do |path|
        next if name == "ruby" && !compatible_ruby?(path)

        return path
      end
      nil
    end

    def command_path(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).filter_map do |directory|
        path = File.join(directory, name)
        path if File.file?(path) && File.executable?(path)
      end.first.to_s
    end

    def compatible_ruby?(path)
      output, status = Open3.capture2e(path, "-e", "print RUBY_VERSION")
      status.success? && Gem::Version.new(output.strip) >= Environment::SUPPORTED_RUBY_MIN
    rescue ArgumentError, SystemCallError
      false
    end

    def check_ruby(root: Environment.repo_root)
      ruby_cmd(root:)
    end

    def runtime_check_skipped?
      return true if ENV["SKIP_RUNTIME_CHECK"] == "1"
      return false if Environment.on_vps? || Environment.on_openbsd?

      !Environment.ruby_version_ok?
    end

    def runtime_skip_reason
      return "SKIP_RUNTIME_CHECK=1" if ENV["SKIP_RUNTIME_CHECK"] == "1"
      return if Environment.on_vps? || Environment.on_openbsd?
      return if Environment.ruby_version_ok?

      Environment.ruby_mismatch_message
    end

    def executable?(name)
      !command_path(name).empty?
    end
  end
end
