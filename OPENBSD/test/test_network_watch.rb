# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

class NetworkWatchTest < Minitest::Test
  SOURCE = File.expand_path("../mirror/usr/local/bin/network-watch.sh", __dir__)

  def setup
    @dir = Dir.mktmpdir("network-watch")
    @bin = File.join(@dir, "bin")
    @state = File.join(@dir, "state")
    FileUtils.mkdir_p([@bin, @state])
    @alerts = File.join(@dir, "alerts.log")
    @script = File.join(@dir, "network-watch.sh")
    source = File.read(SOURCE).sub("ALERT_BIN=/usr/local/bin/pub5-alert", "ALERT_BIN=#{File.join(@bin, "pub5-alert")}")
    File.write(@script, source)
    File.chmod(0o755, @script)
    fake("netstat", <<~SH)
      printf 'Name Mtu Network Address Ibytes Obytes\\n'
      if [ "${FAKE_NETSTAT_MISSING:-0}" = 0 ]; then
        printf 'vio0 1500 Link 00:00:00:00:00:00 %s %s\\n' "${FAKE_RX:-1000}" "${FAKE_TX:-2000}"
      fi
    SH
    fake("pub5-alert", 'printf "%s\\n" "$*" >> "$FAKE_ALERT_LOG"')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def fake(name, body)
    path = File.join(@bin, name)
    File.write(path, ["#!/bin/sh", body].join("\n") + "\n")
    File.chmod(0o755, path)
  end

  def env(extra = {})
    {
      "PUB5_NETWORK_PATH_PREFIX" => @dir,
      "PUB5_NETWORK_STATE_DIR" => @state,
      "PUB5_NETWORK_LOG" => File.join(@dir, "network.log"),
      "FAKE_ALERT_LOG" => @alerts
    }.merge(extra)
  end

  def run_monitor(extra = {})
    Open3.capture3(env(extra), ENV.fetch("PUB5_KSH", "ksh"), @script)
  end

  def test_first_sample_establishes_a_baseline_without_alerting
    _, _, status = run_monitor

    assert status.success?
    assert File.file?(File.join(@state, "network-vio0"))
    assert File.file?(File.join(@state, "network-watch.seen"))
    assert_empty File.read(@alerts) if File.exist?(@alerts)
  end

  def test_outbound_threshold_alerts_on_measured_average_rate
    File.write(File.join(@state, "network-vio0"), "#{Time.now.to_i - 300} 1000 2000\n")
    _, _, status = run_monitor(
      "FAKE_RX" => "2000",
      "FAKE_TX" => "20000000",
      "PUB5_NET_WARN_TX_BPS" => "500000"
    )

    assert status.success?
    assert_includes File.read(@alerts), "network-egress-high"
    assert_includes File.read(File.join(@dir, "network.log")), "avg_tx_bps="
  end

  def test_counter_reset_starts_a_new_baseline_without_negative_alerts
    File.write(File.join(@state, "network-vio0"), "#{Time.now.to_i - 300} 9000 9000\n")
    _, _, status = run_monitor("FAKE_RX" => "1000", "FAKE_TX" => "2000")

    assert status.success?
    assert_includes File.read(File.join(@dir, "network.log")), "counter_reset=1"
    assert_empty File.read(@alerts) if File.exist?(@alerts)
  end

  def test_missing_interface_counters_raise_a_monitor_alert
    _, _, status = run_monitor("FAKE_NETSTAT_MISSING" => "1")

    refute status.success?
    assert_includes File.read(@alerts), "network-monitor-unavailable"
  end
end
