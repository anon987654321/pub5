# frozen_string_literal: true

require "open3"
require "shellwords"
require_relative "canary"

module Operator
  # Builds each target's production assets here and stages them on vm23, stamped
  # with the pinned commit, before the deploy launches. vm23 never compiles: the
  # deploy reads public/assets/.manifest.json and .pub5-build-sha as an
  # attestation and refuses when either is absent or names another commit. Those
  # files had readers and no writer, so every MASTER web and Rails deploy refused
  # at the asset check (vm23, 2026-11-25).
  class AssetStage
    STAMP = ".pub5-build-sha"
    BUILD_TIMEOUT = 900

    # Rails apps read assets from /home/<app>/app/public/assets, which the sync
    # carries forward and which must belong to the app user. MASTER web reads
    # them from dev's own checkout, so it needs no root.
    Target = Struct.new(:name, :local_dir, :remote_dir, :owner, keyword_init: true) do
      def self.for(root, row)
        name = row.name
        public_assets = File.join(row.deploy_root, "public", "assets")
        local = File.join(root, public_assets)
        if row.deploy_group == "master"
          return new(name:, local_dir: local, owner: "dev", remote_dir: "/home/dev/pub5/#{public_assets}")
        end

        new(name:, local_dir: local, owner: name, remote_dir: "/home/#{name}/app/public/assets")
      end

      def app_dir = File.dirname(local_dir, 2)

      # Unpacks a tar stream on the box. Existing digested files stay, so the
      # release still serving keeps its own.
      def unpack_command
        dir = Shellwords.escape(remote_dir)
        return "mkdir -p #{dir} && tar -xf - -C #{dir}" if owner == "dev"

        user = Shellwords.escape(owner)
        make = [File.dirname(remote_dir, 2), File.dirname(remote_dir), remote_dir].map do |path|
          quoted = Shellwords.escape(path)
          "[ -d #{quoted} ] || install -d -o #{user} #{quoted}"
        end

        script = ["set -e", *make, "tar -xf - -C #{dir}", "chown -R #{user} #{dir}"].join("; ")
        "doas sh -c #{Shellwords.escape(script)}"
      end
    end

    def self.targets(root:, app:)
      inventory = Deploy::Inventory.new(root:)
      kind = inventory.target_kind(app)

      rows = if kind == :app
               inventory.apps.select { |row| row.name.casecmp?(app) }
             elsif %i[group all].include?(kind)
               inventory.ordered_apps(group: (app if kind == :group))
             else
               []
             end

      rows.map { |row| Target.for(root, row) }
    end

    def initialize(root:, sha:, ssh:, out: $stdout)
      @root = root
      @sha = sha
      @ssh = ssh
      @out = out
    end

    # [true, nil] once every target is built and staged; [false, reason] at the
    # first failure, before anything is launched on the box.
    def run(app)
      self.class.targets(root: @root, app:).each do |target|
        name = target.name
        @out.puts("assets0: #{name} built here for #{@sha[0, 9]}")
        built, detail = build(target)
        return [false, "#{name} asset build failed here: #{detail}"] unless built

        staged, detail = upload(target)
        return [false, "#{name} assets could not be staged on the box: #{detail}"] unless staged

        @out.puts("assets0: #{name} staged at #{target.remote_dir}")
      end
      [true, nil]
    end

    def build(target)
      dir = target.local_dir
      output, status = Master::Io::Exec.capture2e(
        build_env, RubyRunner.ruby_cmd(root: @root), "bin/rails", "assets:clobber", "assets:precompile",
        chdir: target.app_dir, timeout: BUILD_TIMEOUT, raise_on_timeout: true
      )
      return [false, output.lines.last(3).join.strip] unless status.success?
      return [false, "no .manifest.json was written"] unless File.size?(File.join(dir, ".manifest.json"))

      File.write(File.join(dir, STAMP), @sha)
      [true, nil]
    rescue Master::Io::Exec::TimeoutError
      [false, "assets:precompile timed out after #{BUILD_TIMEOUT}s"]
    end

    # A ustar stream without macOS metadata, so no ._ files reach the box.
    def upload(target)
      tar = [{ "COPYFILE_DISABLE" => "1" }, "tar", "--format", "ustar", "--no-mac-metadata", "--no-xattrs",
             "-C", target.local_dir, "-cf", "-", "."]
      failed = Open3.pipeline(tar, @ssh + [target.unpack_command]).reject(&:success?)
      failed.empty? ? [true, nil] : [false, "tar or ssh exited #{failed.map(&:exitstatus).join(', ')}"]
    end

    private

    def build_env
      cleared = DeployPreflight::FOREIGN_BUNDLE_ENV.to_h { [_1, nil] }
      ENV.each_key { |key| cleared[key] = nil if key.start_with?("BUNDLER_ORIG_") }
      path = "#{File.dirname(RubyRunner.ruby_cmd(root: @root))}:#{ENV.fetch("PATH", "")}"
      cleared.merge("PATH" => path, "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1")
    end
  end
end
