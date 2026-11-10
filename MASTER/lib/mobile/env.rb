# frozen_string_literal: true

module Master
  module Mobile
    CONFIG_PATH = File.expand_path("../../data/mobile.yml", __dir__)

    # data/mobile.yml, read once. A missing or unreadable file is an empty profile.
    # yaml loads here, not at file top: env.rb loads beside mobile/audited_exec
    # during boot, before the locked default gems can be pinned, and an eager
    # require activated the default psych on a fresh checkout (Bundler.setup
    # then refused the locked psych).
    def self.config(path = CONFIG_PATH)
      require "yaml"
      @config ||= {}
      @config[path] ||= File.file?(path) ? (YAML.safe_load_file(path) || {}) : {}
    end

    # Probes of the phone this runs on. Nothing here changes anything.
    module Env
      module_function

      def termux?(env = ENV)
        # PRoot-Distro's normal guest binds /data/data/com.termux into Linux.
        # A directory-existence probe therefore misidentifies Debian/Ubuntu as
        # the Termux host and attempts to run pkg from inside the guest.
        return false if env["container"] == "proot-distro" || !env["PD_CONTAINER"].to_s.empty?

        return true if env["TERMUX_VERSION"]
        return true if env["PREFIX"].to_s.include?("com.termux")

        File.directory?("/data/data/com.termux")
      end

      def forced_mobile?(env = ENV) = env["MASTER_PROFILE"].to_s.strip == "mobile"

      def mobile?(env = ENV) = forced_mobile?(env) || termux?(env)

      # `command -v` is a shell builtin, so system("command", ...) never finds
      # anything; the PATH walk is done here instead.
      def on_path?(name, env = ENV)
        env["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, name.to_s)
          File.file?(path) && File.executable?(path)
        end
      end

      def package_installed?(name)
        name = name.to_s
        return false if name.empty?
        return system("dpkg", "-s", name, out: File::NULL, err: File::NULL) if on_path?("dpkg")

        on_path?(name)
      end

      def ruby_ok?(min_version)
        Gem::Version.new(RUBY_VERSION) >= Gem::Version.new(min_version.to_s)
      rescue ArgumentError
        false
      end
    end
  end
end
