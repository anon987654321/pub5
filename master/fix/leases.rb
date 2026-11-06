# frozen_string_literal: true

module Fix
  # Where each app lives: registry/apps.yml's deploy_root, the one reader
  # (pub4 896032c949: /fix crashed after 90 minutes building RAILS/<name>
  # after master moved). pub5 spells the trees in lower case, so a root
  # written in pub4's spelling is found at its lower-case twin; an app found
  # at neither is reported missing, not fatal.
  module Apps
    Row = Data.define(:name, :port, :dir)

    module_function

    def all(world)
      Core::Registry.load(:apps).fetch("apps").filter_map do |name, app|
        root = app["deploy_root"] or next
        dir = [root, root.sub(%r{\A[^/]+}, &:downcase)].find { |d| spelled?(world.manifest.root, d) }
        Row.new(name:, port: app["port"], dir:)
      end
    end

    # Each segment exists under exactly this spelling: a case-insensitive
    # filesystem answers RAILS/brgen for rails/brgen, git does not.
    def spelled?(root, relative)
      relative.split("/").reduce(root) do |parent, name|
        return false unless File.directory?(parent) && Dir.children(parent).include?(name)

        File.join(parent, name)
      end
      true
    end

    def present(world) = all(world).select(&:dir)

    def missing(world) = all(world).reject(&:dir).map(&:name)
  end

  # The app servers this process booted and owns (pub4 d9cd10098f). A lease
  # file beside each pid file names the owning process; an at_exit hook,
  # installed with the first lease, stops them on TERM, INT or any other
  # exit, and every run starts by reaping the leases whose owner is dead,
  # so a run killed past both does not leave servers holding ports for hours.
  # A lease whose pid file is gone or names another pid is stale and only
  # cleared: that server is not the dead run's. World has no delete verb, so
  # a cleared file is written empty.
  module ServerLeases
    DIR = "tmp/fix/leases"

    @held = []

    module_function

    def pid_path(app) = File.join(DIR, "#{app}.pid")

    def owner_path(app) = "#{pid_path(app)}.owner"

    def hold(world, app, pid)
      world.write(pid_path(app), "#{pid}\n")
      world.write(owner_path(app), "#{Process.pid} #{pid}\n")
      @held << [world, app]
      @exit_hook ||= at_exit { stop_all! }
    end

    def held = @held.dup

    def stop_all!
      @held.each { |world, app| stop(world, app) }
      @held.clear
    end

    def stop(world, app)
      pid = read(world, pid_path(app)).to_i
      world.exec("kill", "-TERM", pid.to_s, timeout: 5) if pid.positive?
      world.write(pid_path(app), "")
      world.write(owner_path(app), "")
    end

    # The apps whose owner is gone, stopped; returns their names.
    def reap_orphans!(world, alive: ->(pid) { world.exec("kill", "-0", pid.to_s, timeout: 5).ok? })
      leases(world).filter_map do |app|
        owner, pid = read(world, owner_path(app)).split.map(&:to_i)
        next if owner.nil? || alive.call(owner)

        live = read(world, pid_path(app)).to_i == pid
        world.write(owner_path(app), "")
        next unless live

        stop(world, app)
        app
      end
    end

    def leases(world)
      dir = File.join(world.manifest.root, DIR)
      return [] unless File.directory?(dir)

      Dir.children(dir).grep(/\.pid\.owner\z/).map { |name| name.delete_suffix(".pid.owner") }.sort
    end

    def read(world, path)
      world.read(path)
    rescue Errno::ENOENT
      ""
    end
  end
end
