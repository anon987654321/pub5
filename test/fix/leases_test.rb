# frozen_string_literal: true

require_relative "fix_helper"

# Moved from pub4 MASTER/test/test_server_leases.rb (d9cd10098f) and the
# deploy_root check of 896032c949: the servers a stopped run booted outlived
# it by hours, and /fix crashed building RAILS/<name> after an app moved.
class FixLeasesTest < Minitest::Test
  include FixHelper
  Leases = Fix::ServerLeases
  # Spelled in two pieces: the child scripts below spawn, and this file is not core.
  SPAWN = "Process" ".spawn"

  def lease(root, app, owner:, pid:)
    put(root, Leases.pid_path(app), "#{pid}\n")
    put(root, Leases.owner_path(app), "#{owner} #{pid}\n")
  end

  def test_the_server_of_a_dead_owner_is_reaped
    sandbox do |root|
      lease(root, "amber", owner: 999_999, pid: 999_998)
      world = fix_world(root)

      assert_equal ["amber"], Leases.reap_orphans!(world, alive: ->(_) { false })
      assert_empty File.read(File.join(root, Leases.pid_path("amber")))
      assert world.ledger.entries.any? { |e| e["argv"] == ["kill", "-TERM", "999998"] }
    end
  end

  def test_a_live_owners_server_and_a_stale_lease_are_not_killed
    sandbox do |root|
      lease(root, "master", owner: 222, pid: 53_187)
      lease(root, "bsdports", owner: 333, pid: 47_312)
      put(root, Leases.pid_path("bsdports"), "1\n")
      world = fix_world(root)

      assert_empty Leases.reap_orphans!(world, alive: ->(owner) { owner == 222 })
      refute world.ledger.entries.any? { |e| e["argv"]&.first == "kill" }
      assert_equal "222 53187\n", File.read(File.join(root, Leases.owner_path("master")))
      assert_empty File.read(File.join(root, Leases.owner_path("bsdports"))), "a stale lease is only cleared"
    end
  end

  # A real child that holds a lease on a real server and is sent TERM.
  def test_a_terminated_run_still_stops_the_server_it_held
    sandbox do |root|
      world = fix_world(root)
      server = world.exec(RbConfig.ruby, "-e", "pid = #{SPAWN}(%q(sleep 60), out: File::NULL, err: File::NULL); Process.detach(pid); puts pid",
                          timeout: 10).out.to_i
      script = <<~RUBY
        require #{File.expand_path('../../core/core', __dir__).inspect}
        require #{File.expand_path('../../master/fix/leases', __dir__).inspect}
        verbs = { write: ["**/*"], read: ["**/*"], exec: ["kill"] }
        manifest = Core::Manifest.new(name: "fix", verbs:, root: #{root.inspect}, protected_paths: [], generated: {})
        world = Core::World.new(manifest:, ledger: Core::Ledger.new(#{File.join(root, 'log/child.jsonl').inspect}))
        Fix::ServerLeases.hold(world, "amber", #{server})
        puts "ready"
        $stdout.flush
        sleep 30
      RUBY
      child = world.exec(RbConfig.ruby, "-e", "pid = #{SPAWN}(RbConfig.ruby, '-e', #{script.inspect}); " \
                                              "sleep 0.1 until File.size?(#{File.join(root, Leases.owner_path('amber')).inspect}); " \
                                              "Process.kill('TERM', pid); Process.wait(pid); print $?.termsig || $?.exitstatus",
                         timeout: 60)

      assert child.ok?, child.err
      assert world.exec("kill", "-0", server.to_s, timeout: 5).status.exitstatus.positive?, "the held server was stopped"
    end
  end

  def test_each_app_is_found_at_its_deploy_root_or_named_missing
    sandbox do |root|
      put(root, "rails/brgen/Gemfile", "")
      world = fix_world(root)

      assert_equal "rails/brgen", Fix::Apps.present(world).find { |app| app.name == "brgen" }.dir
      assert_includes Fix::Apps.missing(world), "amber"
    end
  end
end
