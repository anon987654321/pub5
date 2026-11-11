# frozen_string_literal: true

require_relative "../io/exec"
require_relative "environment"

module Operator
  module RubyRunner
    module_function

    # The current process interpreter is authoritative when compatible. Only
    # search other installed Rubies when this process is below the runtime floor.
    RUBY_NAMES = %w[ruby].freeze

    def ruby_cmd(root: Environment.repo_root)
      explicit = ENV["PUB5_RUBY"].to_s
      unless explicit.empty?
        version = version_for(explicit)
        return explicit if File.executable?(explicit) && version && version >= Environment::SUPPORTED_RUBY_MIN

        raise "PUB5_RUBY must name an executable Ruby >= #{Environment::SUPPORTED_RUBY_MIN}: #{explicit}"
      end

      candidate = best_available_ruby(root:)
      return candidate[:path] if candidate

      raise(Environment.ruby_mismatch_message || "no compatible Ruby found")
    end

    def bundle_cmd(root: Environment.repo_root)
      explicit = ENV["PUB5_BUNDLE"].to_s
      return explicit if !explicit.empty? && File.executable?(explicit)

      ruby = best_available_ruby(root:)&.fetch(:path, nil)
      candidates = []
      candidates << File.join(File.dirname(ruby), "bundle") if ruby
      home = File.expand_path("~")
      candidates.concat(
        [
          File.join(home, "bin", "bundle"),
          File.join(home, ".local", "bin", "bundle"),
          File.join(home, ".rbenv", "shims", "bundle"),
        ],
      )
      candidates << openbsd_path("bundle", root:)
      candidates << command_path("bundle")
      candidates.compact.find { |candidate| File.executable?(candidate) } || "bundle"
    end

    def best_available_ruby(root: Environment.repo_root)
      current = RbConfig.ruby
      current_version = version_for(current)
      return { path: current, version: current_version, current: true } if current_version && current_version >= Environment::SUPPORTED_RUBY_MIN

      candidates = Dir.glob(File.join(rbenv_root_for(root), "versions", "*", "bin", "ruby"))
      candidates.concat(path_ruby_candidates)
      candidates.uniq.filter_map do |path|
        version = version_for(path)
        next unless version && version >= Environment::SUPPORTED_RUBY_MIN

        { path:, version:, current: false }
      end.max_by { |candidate| candidate[:version] }
    end

    # Discover versioned package names as well as ruby on PATH. This prevents
    # a stale list of package names becoming an accidental upper bound.
    def path_ruby_candidates
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).flat_map do |directory|
        next [] unless File.directory?(directory)

        Dir.children(directory).filter_map do |name|
          next unless name.match?(/\Aruby(?:\d+(?:\.\d+)*)?\z/)

          path = File.join(directory, name)
          path if File.file?(path) && File.executable?(path)
        end
      rescue SystemCallError
        []
      end
    end

    def same_interpreter?(left, right)
      File.identical?(left, right)
    rescue SystemCallError
      File.expand_path(left.to_s) == File.expand_path(right.to_s)
    end

    def rbenv_root_for(_root)
      root = ENV["RBENV_ROOT"].to_s
      root.empty? ? File.expand_path("~/.rbenv") : root
    end

    RBENV_VERSION_DIR = %r{/versions/(\d+(?:\.\d+)+)/bin/ruby\z}

    # Asked of an interpreter only when nothing cheaper knows: the running Ruby says RUBY_VERSION, an rbenv
    # Ruby's directory names its version, and each other path is asked once. Spawning every candidate cost
    # 0.9s of each MASTER boot, because loading check_chain.rb asks for the best Ruby.
    def version_for(path)
      return Gem::Version.new(RUBY_VERSION) if File.identical?(path, RbConfig.ruby)

      named = path.to_s[RBENV_VERSION_DIR, 1]
      return Gem::Version.new(named) if named

      (@versions ||= {}).fetch(path) { @versions[path] = spawned_version(path) }
    end

    def spawned_version(path)
      output, status = Master::Io::Exec.capture2e(path, "-e", "print RUBY_VERSION")
      return unless status.success?

      Gem::Version.new(output.to_s.strip[/\d+(\.\d+)+\z/])
    rescue ArgumentError, Errno::ENOEXEC, Errno::EACCES
      nil
    end

    # Alternative packaged runtimes are consulted only when the current Ruby
    # is below the compatibility floor; no repository patch release is preferred.
    def openbsd_path(name, root: Environment.repo_root)
      return unless RUBY_PLATFORM.match?(/openbsd/)

      prefix = name.to_s
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        next unless File.directory?(directory)

        Dir.children(directory).sort.each do |entry|
          next unless entry.match?(/\A#{Regexp.escape(prefix)}(?:[0-9]+(?:\.[0-9]+)*)?\z/)

          path = File.join(directory, entry)
          next unless File.file?(path) && File.executable?(path)
          if name.to_s == "ruby"
            version = version_for(path)
            next unless version && version >= Environment::SUPPORTED_RUBY_MIN
          end
          return path
        end
      rescue SystemCallError
        next
      end
      nil
    end

    def command_path(name) = Master::Io::Exec.which(name).to_s

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
  end
end
