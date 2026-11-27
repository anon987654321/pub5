# frozen_string_literal: true

require_relative "test_helper"

class CapabilityCatalogTest < Minitest::Test
  Catalog = Master::Ground::CapabilityCatalog

  def test_catalog_distinguishes_core_tools_from_plugin_integration_units
    result = Catalog.call(action: "list")

    assert_equal "ok", result.fetch("status")
    assert result.fetch("core_tools").any? { |tool| tool["name"] == "ReadFile" && tool["elevated_required"] == false }
    plugin = result.fetch("plugins").find { |item| item["id"] == "session_browser" }
    assert plugin
    assert_equal %w[status inspect], plugin.fetch("observation_actions").map { |row| row["name"] }
    assert plugin.fetch("observation_actions").all? { |row| row["access"] == "read_only" }
    assert_includes %w[declared policy_missing no_observation_actions], plugin.fetch("status")
    assert_match(/not proof of live availability/, result.fetch("note"))
  end

  def test_search_returns_matching_tools_and_plugins
    result = Catalog.call(action: "search", query: "browser")
    names = result.fetch("results").map { |item| item["name"] || item["id"] }

    assert_includes names, "Browser"
    assert_includes names, "session_browser"
  end

  def test_describe_supports_a_builtin_tool_plugin_and_declared_action
    assert_equal "core_tool", Catalog.call(action: "describe", name: "ReadFile").fetch("kind")
    assert_equal "plugin", Catalog.call(action: "describe", name: "session_browser").fetch("kind")
    result = Catalog.call(action: "describe", name: "plugin:session_browser:status")
    assert_equal "plugin_observation", result.fetch("kind")
    assert_equal "read_only", result.fetch("capability").fetch("access")
  end

  def test_unknown_descriptions_and_empty_search_are_explicit
    assert_equal "not_found", Catalog.call(action: "describe", name: "not_registered").fetch("status")
    assert_raises(ArgumentError) { Catalog.call(action: "search", query: " ") }
    assert_raises(ArgumentError) { Catalog.call(action: "execute", name: "Browser") }
  end
end

require_relative "test_helper"
require_relative "../lib/operator/capability_graph"

class TestCapabilityGraph < Minitest::Test
  def test_executable_state_uses_real_executables_from_path
    Dir.mktmpdir("capability-path") do |dir|
      executable = File.join(dir, "afplay")
      plain_file = File.join(dir, "pactl")
      directory = File.join(dir, "termux-media-player")
      File.write(executable, "#!/bin/sh\n")
      File.chmod(0o755, executable)
      File.write(plain_file, "not executable")
      Dir.mkdir(directory)

      graph = Operator::CapabilityGraph.new(root: dir, path: File.join(dir, "capabilities.json"))
      previous_path = ENV["PATH"]
      begin
        ENV["PATH"] = dir
        assert_equal "available", graph.send(:executable_state, %w[afplay])
        assert_equal "unavailable", graph.send(:executable_state, %w[pactl])
        assert_equal "unavailable", graph.send(:executable_state, %w[termux-media-player])
      ensure
        previous_path.nil? ? ENV.delete("PATH") : ENV["PATH"] = previous_path
      end
    end
  end
end

require "minitest/autorun"
require "master"

class CapabilityLawTest < Minitest::Test
  def test_capability_reduction_is_implemented_and_monotonic
    capabilities = Master::Core::Capabilities.for(:fix)

    capabilities.drop(:network)
    assert_raises(SecurityError) { capabilities.acquire(:network) }
    assert_raises(SecurityError) { capabilities.require!(:network) }

    capabilities.lock!
    assert_raises(SecurityError) { capabilities.drop(:read) }
  end

  def test_read_only_modes_fetch_the_web_but_never_write_or_execute
    %i[observe plan].each do |profile|
      capabilities = Master::Core::Capabilities.for(profile)

      assert capabilities.allows?(:network), "#{profile} cannot fetch a page"
      refute capabilities.allows?(:write), "#{profile} can write"
      refute capabilities.allows?(:execute), "#{profile} can execute"
    end
  end
end

require_relative "test_helper"
require_relative "../lib/operator/capability_manifest"

class TestCapabilityManifest < Minitest::Test
  def test_unexercised_capabilities_are_not_reported_as_available
    manifest = Operator::CapabilityManifest.new(root: Master::ROOT).call
    capabilities = manifest.fetch("capabilities")
    %w[local_shell remote_shell browser github_api test_execution].each do |name|
      assert_equal "not_probed", capabilities.fetch(name).fetch("status")
    end
  end

  def test_running_ruby_is_grounded_in_the_current_process
    manifest = Operator::CapabilityManifest.new(root: Master::REPO_ROOT).call
    assert_equal "available", manifest.dig("capabilities", "ruby_runtime", "status")
    assert_includes manifest.dig("capabilities", "ruby_runtime", "evidence"), RUBY_VERSION
  end

  def test_write_permission_is_not_mislabelled_as_a_completed_write
    manifest = Operator::CapabilityManifest.new(root: Master::REPO_ROOT).call
    status = manifest.dig("capabilities", "repository_write_permission", "status")
    assert_includes %w[permission_observed permission_denied], status
  end
end

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "time"

class CapabilityStampTest < Minitest::Test
  def health_at(dir, at:, status: :success, model: "grok-cli:opus")
    health = Master::CLI::Routing::ProviderHealth.new(
      path: File.join(dir, "runtime", "telemetry", "provider_health.ndjson"),
      now: -> { at },
    )
    health.record(model:, status:, at:)
    health
  end

  def test_stamp_reports_fresh_cloud_model
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 9, 28, 13, 0, 0)
      recorded = health_at(dir, at: now - 41, model: "grok-cli:opus")
      health = Master::CLI::Routing::ProviderHealth.new(path: recorded.path, now: -> { now })
      policy = Master::CLI::Routing::AvailabilityPolicy.new(root: dir)

      assert_equal(
        "model0 at master0: served grok-cli:opus, level L4, health fresh 41s, degraded no",
        Master::CLI::CapabilityStamp.render(model: "grok-cli:opus", root: dir, provider_health: health, policy:),
      )
    end
  end

  def test_stamp_reports_stale_evidence_without_calling_it_healthy
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 9, 28, 13, 0, 0)
      health = health_at(dir, at: now - 180, model: "web-chat:grok")
      health_now = Master::CLI::Routing::ProviderHealth.new(
        path: health.path,
        now: -> { now },
      )
      policy = Master::CLI::Routing::AvailabilityPolicy.new(root: dir)

      assert_equal(
        "model0 at master0: served web-chat:grok, level L3, health stale 180s, degraded yes",
        Master::CLI::CapabilityStamp.render(model: "web-chat:grok", root: dir, provider_health: health_now, policy:),
      )
    end
  end

  def test_stamp_marks_unobserved_model_as_unknown
    Dir.mktmpdir do |dir|
      policy = Master::CLI::Routing::AvailabilityPolicy.new(root: dir)

      assert_equal(
        "model0 at master0: served ollama:qwen3, level L2, health unknown, degraded unknown",
        Master::CLI::CapabilityStamp.render(model: "ollama:qwen3", root: dir, policy:),
      )
    end
  end
end

require "minitest/autorun"
require "master"
require_relative "../lib/operator/services"

class CapabilityStatusTest < Minitest::Test
  def test_voice_status_reports_retained_runtime_failure
    speech = Master::Voice::Speech
    playback = Master::Voice::Playback
    original_speech = speech.instance_variable_get(:@last_error)
    original_playback = playback.instance_variable_get(:@last_error)

    speech.instance_variable_set(:@last_error, "edge socket produced empty audio")
    playback.instance_variable_set(:@last_error, "audio playback failed - afplay")
    status = Master::Operator.status("voice")["voice"]

    assert_match(/degraded:/, status)
    assert_match(/edge socket produced empty audio|audio playback failed/, status)
  ensure
    speech.instance_variable_set(:@last_error, original_speech)
    playback.instance_variable_set(:@last_error, original_playback)
  end
end
