# frozen_string_literal: true

require_relative "../io/exec"
require_relative "environment"

module Operator
  module RubyRunner
    module_function

    # Use the interpreter that booted MASTER first. Alternate installed Rubies
    # are a recovery path only when the current runtime is below the project floor.
    RUBY_NAMES = %w[ruby ruby4.2 ruby42 ruby4.1 ruby41 ruby4.0 ruby40 ruby3.4 ruby34 ruby3.3 ruby33].freeze

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
      if current_version && current_version >= Environment::SUPPORTED_RUBY_MIN
        return { path: current, version: current_version }
      end

      candidates = Dir.glob(File.join(rbenv_root_for(root), "versions", "*", "bin", "ruby"))
      RUBY_NAMES.each do |name|
        path = command_path(name)
        candidates << path unless path.empty?
      end

      candidates.uniq.filter_map do |path|
        version = version_for(path)
        next unless version && version >= Environment::SUPPORTED_RUBY_MIN

        { path:, version: }
      end.max_by { |candidate| candidate[:version] }
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

      RUBY_NAMES.each do |ruby_command|
        command = name == "ruby" ? ruby_command : ruby_command.sub(/\Aruby/, name)
        path = command_path(command)
        return path unless path.empty?
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
