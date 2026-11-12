# frozen_string_literal: true

require_relative "test_helper"

class TestHeartbeat < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize = @events = []

    def publish(event, payload = {})
      @events << { event:, payload: }
    end
  end

  # Heartbeat#load_jobs reads data/patterns.yml#heartbeat; a fixture written
  # anywhere else runs the default job list instead, which the snapshot refute
  # below would catch.
  def test_self_test_job_is_enabled_hourly_from_config
    Dir.mktmpdir do |root|
      write_heartbeat_jobs(root, <<~YAML)
        - name: self_test
          action: self_test
          interval_seconds: 3600
          enabled: true
      YAML

      heartbeat = Master::Fix::Heartbeat.new(root:)

      assert_includes heartbeat.list, "self_test: every 60m"
      refute_includes heartbeat.list, "snapshot", "default jobs must not leak in when config is present"
    end
  end

  def test_self_test_heartbeat_publishes_clean_scan_metrics
    Dir.mktmpdir do |root|
      write_heartbeat_root(root, <<~YAML)
        self_test:
          ROBUSTNESS: "scan lib/ for bare_rescue + missing timeouts"
      YAML
      bus = FakeBus.new
      heartbeat = Master::Fix::Heartbeat.new(root:, scanner: Object.new, event_bus: bus)

      heartbeat.run_due!

      clean = bus.events.find { |entry| entry[:event] == "heartbeat:scan_clean" }
      assert clean
      assert_equal 0, clean[:payload][:violations]
      assert_operator clean[:payload][:last_fixed], :>, 0
    end
  end

  def test_prune_undo_targets_the_canonical_journal_and_keeps_the_latest_entries
    Dir.mktmpdir do |root|
      master_dir = File.join(root, ".master")
      FileUtils.mkdir_p(master_dir)
      journal = File.join(master_dir, "undo_journal.jsonl")
      wrong_legacy_path = File.join(master_dir, "undo.jsonl")
      rows = 55.times.map do |index|
        { "path" => "file-#{index}", "content" => "before-#{index}", "ts" => index }
      end
      File.write(journal, rows.map { |row| JSON.generate(row) + "\n" }.join)
      File.write(wrong_legacy_path, "leave this unrelated file alone\n")

      result = Master::Fix::Heartbeat.new(root:).send(:prune_undo_journal)

      retained = File.readlines(journal).map { |line| JSON.parse(line) }
      assert_match(/removed 5 entries/, result)
      assert_equal 50, retained.size
      assert_equal "file-5", retained.first.fetch("path")
      assert_equal "file-54", retained.last.fetch("path")
      assert_equal "leave this unrelated file alone\n", File.read(wrong_legacy_path)
      assert_equal 0o600, File.stat(journal).mode & 0o777
    end
  end

  def test_personal_pulse_returns_heartbeat_ok_when_nothing_to_say
    Dir.mktmpdir do |root|
      write_heartbeat_jobs(root, <<~YAML)
        - name: personal_pulse
          action: personal_pulse
          interval_seconds: 0
          enabled: true
      YAML

      results = Master::Fix::Heartbeat.new(root:).run_due!
      pulse = results.find { |row| row[:name] == "personal_pulse" }
      assert pulse
      assert_equal "HEARTBEAT_OK", pulse[:result]
    end
  end

  def test_self_test_heartbeat_publishes_violation_metrics_with_last_fixed
    Dir.mktmpdir do |root|
      write_heartbeat_root(root, <<~YAML)
        self_test:
          ROBUSTNESS: "scan lib/ for bare_rescue + missing timeouts"
        rules:
          - id: DUPLICATE
            name: one
          - id: DUPLICATE
            name: two
      YAML
      FileUtils.mkdir_p(File.join(root, ".master"))
      File.write(File.join(root, ".master", "heartbeat_state.yml"), { "self_test" => { "last_fixed" => 123 } }.to_yaml)
      bus = FakeBus.new
      heartbeat = Master::Fix::Heartbeat.new(root:, scanner: Object.new, event_bus: bus)

      heartbeat.run_due!

      violations = bus.events.find { |entry| entry[:event] == "heartbeat:violations" }
      assert violations
      assert_operator violations[:payload][:violations], :>, 0
      assert_equal 123, violations[:payload][:last_fixed]
    end
  end

  private

  def write_heartbeat_jobs(root, jobs_yaml)
    FileUtils.mkdir_p(File.join(root, "data"))
    File.write(File.join(root, "data", "patterns.yml"), { "heartbeat" => YAML.safe_load(jobs_yaml) }.to_yaml)
  end

  def write_heartbeat_root(root, rules_yaml)
    FileUtils.mkdir_p(File.join(root, "lib"))
    write_heartbeat_jobs(root, <<~YAML)
      - name: self_test
        action: self_test
        interval_seconds: 0
        enabled: true
    YAML
    # SelfTest's LAW_MAP check reports "missing laws.yml#law_map" against a bare
    # fixture root, so the clean case needs an empty map, which satisfies
    # integrity. It is merged with the case's own laws, not written over them,
    # because the violations case needs its duplicate ids.
    law_map = { "schema" => 1, "version" => "test-fixture", "laws" => {} }
    laws = (YAML.safe_load(rules_yaml) || {}).merge("law_map" => law_map)
    File.write(File.join(root, "data", "laws.yml"), laws.to_yaml)
  end
end
