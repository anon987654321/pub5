# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "yaml"
require_relative "../lib/fix/surface_evidence"

class TestSurfaceEvidenceContract < Minitest::Test
  def evidence = Master::Fix::SurfaceEvidence.allocate

  def capture_row(overrides = {})
    {
      "rendered_status" => "assessed_clean",
      "screenshot_sha256" => "a" * 64,
      "geometry_sha256" => "b" * 64,
      "element_count" => 12,
    }.merge(overrides)
  end

  def test_rendered_capture_requires_screenshot_geometry_and_element_receipt
    assert evidence.send(:valid_rendered_capture?, capture_row)
    refute evidence.send(:valid_rendered_capture?, capture_row("screenshot_sha256" => nil))
    refute evidence.send(:valid_rendered_capture?, capture_row("geometry_sha256" => "missing"))
    refute evidence.send(:valid_rendered_capture?, capture_row("element_count" => "unknown"))
    refute evidence.send(:valid_rendered_capture?, capture_row("element_count" => -1))
    refute evidence.send(:valid_rendered_capture?, capture_row("rendered_status" => "inconclusive"))
  end

  def test_ruby_and_erb_syntax_probes_handle_parse_errors_without_catching_fatal_exceptions
    scripts = %i[RUBY_SYNTAX_PROBE ERB_SYNTAX_PROBE].map do |name|
      Master::Fix::SurfaceEvidence.const_get(name, false)
    end

    scripts.each do |script|
      assert_includes script, "rescue StandardError, ScriptError => error"
      refute_includes script, "rescue Exception"
    end
  end

  def test_media_inventory_does_not_ignore_symlinked_assets
    inventory = {
      "records" => [
        ["public/logo.svg", "file", 120],
        ["public/private-logo.png", "symlink", 0],
        ["README.md", "file", 50],
      ],
    }

    rows = evidence.send(:recognized_asset_records, inventory)

    assert_equal [["public/logo.svg", "file", 120], ["public/private-logo.png", "symlink", 0]], rows
  end

  def test_openbsd_deploy_inventory_matches_the_canonical_rails_app_registry
    root = File.expand_path("../..", __dir__)
    rails = YAML.safe_load_file(File.join(root, "RAILS", "apps.yml"), aliases: true)
    inventory = JSON.parse(File.read(File.join(root, "OPENBSD", "deploy_inventory.json"), encoding: "UTF-8"))

    assert_equal rails.fetch("apps").keys.sort, inventory.fetch("apps").map { |row| row.fetch("name") }.sort
    assert_equal "RAILS/apps.yml", inventory.fetch("generated_from")
    master = inventory.fetch("apps").find { |row| row.fetch("name") == "master" }
    assert_equal rails.dig("apps", "master", "port"), master.fetch("port")
    assert_equal "MASTER/web", rails.dig("apps", "master", "deploy_root")
    assert File.executable?(File.join(root, "OPENBSD", "bin", "vps-deploy"))
  end

  def test_compact_visual_evidence_keeps_geometry_receipt_without_page_content
    row = capture_row.merge("id" => "surface-1", "url" => "https://private.invalid/path?token=secret")
    compact = evidence.send(:compact_visual_row, row)

    assert_equal "b" * 64, compact.fetch("geometry_sha256")
    assert_equal 12, compact.fetch("element_count")
    refute compact.to_s.include?("private.invalid")
    refute compact.to_s.include?("secret")
  end
  def test_process_group_signal_never_falls_back_to_the_numeric_leader_pid
    calls = []
    Process.stub(:kill, lambda { |signal, target|
      calls << [signal, target]
      raise Errno::EPERM
    }) do
      refute evidence.send(:signal_group, "TERM", 1234)
    end

    assert_equal [["TERM", -1234]], calls
  end

  def test_missing_owned_process_group_is_already_stopped_without_pid_fallback
    calls = []
    Process.stub(:kill, lambda { |signal, target|
      calls << [signal, target]
      raise Errno::ESRCH
    }) do
      assert evidence.send(:signal_group, "TERM", 1234)
    end

    assert_equal [["TERM", -1234]], calls
  end

  def test_process_group_stop_refuses_the_callers_own_group
    group = Process.getpgrp

    refute evidence.send(:stop_process_group, group, term_grace: 0, kill_grace: 0)
    assert_equal group, Process.getpgrp
  end

  def test_runtime_probe_routes_each_language_to_its_parser_without_shell_interpolation
    instance = evidence
    source_class = Struct.new(:path)
    instance.instance_variable_set(:@root, Dir.pwd)
    instance.instance_variable_set(:@plan, Struct.new(:sources).new(
      %w[app.rb app.erb app.js app.ts app.sh app.ksh app.zsh].map { |path| source_class.new(path) }
    ))
    instance.define_singleton_method(:deadline_remaining) { |_deadline| 30 }
    instance.define_singleton_method(:executable_path) { |name| "/usr/bin/#{name}" }
    instance.define_singleton_method(:execute_command) do |*_args, **_options|
      { "status" => "passed" }
    end
    instance.define_singleton_method(:rails_runtime_probes) do |_deadline|
      { failures: [], unavailable: [], checked: [] }
    end

    result = instance.send(:runtime_probe_outcomes, 60)

    assert_equal 1, result.dig(:checked, "ruby")
    assert_equal 1, result.dig(:checked, "erb")
    assert_equal 1, result.dig(:checked, "javascript")
    assert_equal 1, result.dig(:checked, "sh")
    assert_equal 1, result.dig(:checked, "ksh")
    assert_equal 1, result.dig(:checked, "zsh")
    assert_empty result.fetch(:failures)
    assert_match(/TypeScript\/JSX/, result.fetch(:unavailable).first)
  end

end
