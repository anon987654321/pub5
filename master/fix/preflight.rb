# frozen_string_literal: true

require "digest"

module Fix
  # Before the first repair (PLAN.md section 6.9): one /fix per tree, and
  # the paths this run will touch parse and hold still.
  #
  # Only the paths /fix itself touches are read. In a checkout other writers
  # share, a file can move between two readings; when every difference is
  # still drift after three readings the run reports it and goes on (pub4
  # 850af52083), because each repair re-reads its file and the transaction
  # refuses to overwrite a concurrent edit. A file that does not parse on a
  # steady reading refuses the run.
  module Preflight
    READINGS = 3
    LOCK_DIR = "tmp/fix/locks"

    Report = Data.define(:broken, :drifting)

    module_function

    def check(world, paths, settle: -> { sleep 0.2 })
      drifting = []
      READINGS.times do |reading|
        first = prints(world, paths)
        broken = Core::ParseGate.check(paths, root: world.manifest.root)
        drifting = (prints(world, paths).to_a - first.to_a).map(&:first)
        return Report.new(broken:, drifting: []) if drifting.empty?

        settle.call unless reading == READINGS - 1
      end
      Report.new(broken: Core::ParseGate.check(paths - drifting, root: world.manifest.root), drifting:)
    end

    def prints(world, paths) = paths.to_h { |path| [path, Digest::SHA256.hexdigest(world.read(path))] }

    # One lock per tree: the file names the holding pid; an empty file or a
    # dead pid is free. World has no delete verb, so release writes it empty.
    def lock!(world, scope)
      path = lock_path(scope)
      holder = (world.read(path).to_i rescue 0)
      if holder.positive? && holder != Process.pid && alive?(world, holder)
        raise Core::Refusal.new(:write, path, "another /fix (pid #{holder}) holds #{scope}")
      end

      world.write(path, "#{Process.pid}\n")
      path
    end

    def release(world, path) = world.write(path, "")

    def lock_path(scope) = File.join(LOCK_DIR, "#{scope.gsub(/[^\w.-]+/, '_')}.lock")

    def alive?(world, pid) = world.exec("kill", "-0", pid.to_s, timeout: 5).ok?
  end
end
