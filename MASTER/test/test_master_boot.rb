# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class MasterBootTest < Minitest::Test
  def test_boot_loader_requires_all_modules
    assert defined?(MasterPaths)
    assert defined?(Master::DataLoading)
    assert defined?(Master::MasterRuntime)
    assert defined?(Master::MasterBoot)
  end

  def test_master_paths_shim_matches_boot_paths
    assert_equal MasterPaths::ROOT, File.expand_path("..", File.expand_path("../lib", __dir__))
    assert MasterPaths.data("laws.yml").end_with?("/data/laws.yml")
  end

  def test_master_data_load_yaml_reads_canonical_laws
    path = Master.data_path("laws.yml")

    body = Master.load_yaml(path)
    assert body.is_a?(Hash)
    # Laws are flat records; executable ones also have a law_catalogue entry.
    # transformation_policy is runtime configuration read through Master.law.
    assert body.key?("SINGULARITY")
    assert body.fetch("law_catalogue").fetch("entries").key?("CAPABILITY_STATUS_MUST_BE_TRUTHFUL")
  end

  def test_master_runtime_process_defaults_constant
    assert_includes Master::MasterRuntime::PROCESS_DEFAULTS, "MASTER_SAFE_MODE"
    assert_equal "1", Master::MasterRuntime::PROCESS_DEFAULTS["MASTER_SAFE_MODE"]
  end

  def test_master_boot_module_exposes_boot_entrypoints
    assert Master.respond_to?(:boot)
    assert Master.respond_to?(:prepare_runtime!)
    assert Master.respond_to?(:validate_data!)
  end

  def test_backlog_runner_uses_scoped_fix_and_records_verified_origin_delivery
    Dir.mktmpdir("backlog-runner") do |mission_root|
      Dir.mktmpdir("backlog-repo") do |repo_root|
        paths = %w[MASTER/lib/a.rb MASTER/lib/b.rb]
        paths.each do |path|
          full = File.join(repo_root, path)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, "VALUE = 1\n")
        end
        plan = JSON.generate(
          "executor" => "root_todo", "item_id" => "item-1",
          "item_digest" => "d" * 64, "scope_paths" => paths,
        )
        goal = "Complete exactly this root TODO item using /fix"
        queued = Master::Fix::Mission.new(root: mission_root).ensure_queued!(
          goal:, scope: mission_root, plan:, origin: "backlog", auto_continue: true,
          mode: "repair", intent: :functional_change,
        )
        seen = []
        report = "fix done - 1 commit delivered - proof: 12 of 12 - hard red 0 - soft red 0"
        command = Object.new
        command.define_singleton_method(:call) do |ctx|
          seen << ctx.fetch(:args)
          report
        end
        fake_git = Object.new
        fake_git.define_singleton_method(:push_target) { ["origin", "HEAD:main"] }
        status = Object.new.tap { |value| value.define_singleton_method(:success?) { true } }
        capture = lambda do |*args, **|
          if args.last(3) == ["remote", "get-url", "origin"]
            ["git@github.com:owner/pub5.git\n", status]
          else
            flunk("unexpected preflight command: #{args.inspect}")
          end
        end
        push = lambda do |mission:, **|
          assert mission.record_repository_push!(
            remote: "origin", branch: "main", commit: "a" * 40
          )
          "a" * 40
        end

        Master::Io::GitOperations.stub(:new, ->(_root) { fake_git }) do
          Master::Io::Exec.stub(:capture2e, capture) do
            Master::CLI::CoreBridge.stub(:push_backlog_commit!, push) do
              result = Master.run_backlog_task(
                root: mission_root, container: { commands: { "fix" => command } },
                mission: queued.record, repo_root:
              )
              assert result.ok?, result.message
            end
          end
        end

        assert_equal paths.map { |path| "#{path} --intent=functional_change" }, seen
        completed = Master::Fix::Mission.current(root: mission_root)
        assert_equal "completed", completed.fetch("state")
        assert_equal "fix_pipeline", completed.dig("proof", "kind")
        assert_equal paths.sort, completed.dig("proof", "scope_paths").sort
        assert_equal "origin", completed.dig("repository_pushes", 0, "remote")
      end
    end
  end

  def test_backlog_runner_blocks_when_fix_report_has_no_measured_proof
    Dir.mktmpdir("backlog-runner") do |mission_root|
      Dir.mktmpdir("backlog-repo") do |repo_root|
        path = "MASTER/lib/a.rb"
        full = File.join(repo_root, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, "VALUE = 1\n")
        plan = JSON.generate("executor" => "root_todo", "item_id" => "item-2",
                             "item_digest" => "e" * 64, "scope_paths" => [path])
        queued = Master::Fix::Mission.new(root: mission_root).ensure_queued!(
          goal: "Complete item 2 using /fix", scope: mission_root, plan:,
          origin: "backlog", auto_continue: true, mode: "repair", intent: :functional_change,
        )
        command = Object.new
        command.define_singleton_method(:call) { |*| "fix done - proof: no proof ran - hard red 0 - soft red 0" }
        fake_git = Object.new
        fake_git.define_singleton_method(:push_target) { ["origin", "HEAD:main"] }
        status = Object.new.tap { |value| value.define_singleton_method(:success?) { true } }
        capture = ->(*, **){ ["git@github.com:owner/pub5.git\n", status] }

        Master::Io::GitOperations.stub(:new, ->(_root) { fake_git }) do
          Master::Io::Exec.stub(:capture2e, capture) do
            result = Master.run_backlog_task(
              root: mission_root, container: { commands: { "fix" => command } },
              mission: queued.record, repo_root:
            )
            refute result.ok?
          end
        end

        blocked = Master::Fix::Mission.current(root: mission_root)
        assert_equal "blocked", blocked.fetch("state")
        assert_match(/FIX_PROOF_FAILED/, blocked.fetch("wake_reason"))
      end
    end
  end

  def test_data_validation_detects_rapid_file_edits
    Dir.mktmpdir do |dir|
      data = File.join(dir, "data")
      FileUtils.mkdir_p(data)
      path = File.join(data, "sample.yml")
      File.write(path, "ok: true\n")
      Master.validate_data!(root: dir)

      File.write(path, "broken: [\n")
      errors = Master.validate_data!(root: dir)

      assert errors.key?("sample.yml"), errors.inspect
    end
  end

  def test_data_validation_reports_invalid_utf8_without_aborting_the_sweep
    Dir.mktmpdir do |dir|
      data = File.join(dir, "data")
      FileUtils.mkdir_p(data)
      path = File.join(data, "invalid.yml")
      File.binwrite(path, [0xFF].pack("C"))

      errors = Master.validate_data!(root: dir)

      assert errors.key?("invalid.yml"), errors.inspect
      assert_match(/invalid UTF-8/, errors.fetch("invalid.yml"))
    end
  end

  def test_data_validation_detects_same_size_edits_with_restored_mtime
    Dir.mktmpdir do |dir|
      data = File.join(dir, "data")
      FileUtils.mkdir_p(data)
      path = File.join(data, "sample.yml")
      File.write(path, "ok: true\n")
      assert_empty Master.validate_data!(root: dir)
      original = File.stat(path)

      malformed = "x: [a,  \n"
      assert_equal original.size, malformed.bytesize
      File.write(path, malformed)
      File.utime(original.atime, original.mtime, path)
      errors = Master.validate_data!(root: dir)

      assert errors.key?("sample.yml"), errors.inspect
    end
  end

  def test_a_missing_yaml_file_warns_once
    Dir.mktmpdir do |dir|
      missing = File.join(dir, "PATH_OWNERSHIP.yml")
      _, err = capture_io { 3.times { assert_equal({}, Master.load_yaml(missing)) } }

      assert_equal 1, err.lines.grep(/\Aboot0: yaml .*PATH_OWNERSHIP\.yml/).size, err
    end
  end

  def test_missing_yaml_defaults_are_not_shared_between_calls
    Dir.mktmpdir do |dir|
      first = Master.load_yaml(File.join(dir, "first.yml"))
      first["polluted"] = true

      second = Master.load_yaml(File.join(dir, "second.yml"))

      assert_equal({}, second)
    end
  end

  # laws.yml needs aliases, which is why load_yaml allows them. Aliases are
  # references inside the document; a Ruby object tag is still refused.
  def test_load_yaml_follows_aliases_and_refuses_ruby_objects
    Dir.mktmpdir do |dir|
      aliased = File.join(dir, "aliased.yml")
      File.write(aliased, "base: &base\n  size: 3\ncopy: *base\n")
      assert_equal({ "size" => 3 }, Master.load_yaml(aliased)["copy"])

      recursive = File.join(dir, "recursive.yml")
      File.write(recursive, "root: &root\n  name: root\n  self: *root\n")
      first = Master.load_yaml(recursive)
      second = Master.load_yaml(recursive)
      assert_equal "root", first.dig("root", "name")
      assert_same first["root"], first["root"]["self"]
      refute_same first["root"], second["root"]
      assert_same second["root"], second["root"]["self"]
      first["root"]["name"] = "changed"
      assert_equal "root", second["root"]["name"]

      tagged = File.join(dir, "tagged.yml")
      File.write(tagged, "--- !ruby/object:OpenStruct\ntable: {}\n")
      assert_raises(Psych::DisallowedClass) { Master.load_yaml(tagged) }
    end
  end

  def test_load_yaml_preserves_false_root_values
    Dir.mktmpdir do |dir|
      path = File.join(dir, "false.yml")
      File.write(path, "false\n")

      assert_equal false, Master.load_yaml(path)
      assert_equal false, Master.load_yaml(path, default: "fallback")
    end
  end
  def test_termux_native_tts_is_ready_without_the_edge_worker
    keys = %w[MASTER_SKIP_TTS MASTER_TTS_DEGRADED MASTER_TTS_REASON]
    saved = keys.to_h { |key| [key, ENV[key]] }
    keys.each { |key| ENV.delete(key) }
    ENV["MASTER_TTS_DEGRADED"] = "1"
    ENV["MASTER_TTS_REASON"] = "edge worker unavailable"

    Master::Device.stub(:android?, true) do
      Master::Device::Audio.stub(:tts_available?, true) do
        Master::Voice::Speech.stub(:available?, false) do
          Master.stub(:supervise_tts, ->(**) { flunk("native Termux TTS must not start Edge") }) do
            assert Master.ensure_services!(root: Master::ROOT)
          end
        end
      end
    end

    refute ENV.key?("MASTER_TTS_DEGRADED")
    refute ENV.key?("MASTER_TTS_REASON")
  ensure
    saved&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

end
