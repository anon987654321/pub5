# frozen_string_literal: true

require "yaml"
require "net/http"
require "uri"

# The dashboard's window onto the rest of the box: sibling app health, the
# machine's load against the guard's thresholds, and the resource guard's shed
# order — the facts CLAUDE.md documents and the console rendered none of.
#
# One source of truth per fact. The app inventory comes from RAILS/apps.yml
# (the canonical ports and domains matrix); the shed order and the thresholds
# are parsed out of OPENBSD's resource_guard.sh, not restated here; load is the
# host's own one-minute average. Every read is bounded and degrades to a panel
# that says so: a dashboard that cannot read one file must still answer for
# the files it read.
module FleetPanel
  APPS_YML = "RAILS/apps.yml"
  GUARD_SCRIPT = "OPENBSD/usr/local/bin/resource_guard.sh"
  # The siblings sharing vm23 with this dashboard. master is the dashboard's
  # own app; the guard's OPTIONAL list, not this constant, owns the shed order.
  SIBLINGS = %w[brgen amber bsdports mrdamascy].freeze
  PROBE_TIMEOUT_S = 0.4
  HEALTH_PATH = "/up"

  module_function

  def read(root:, probe: nil, load_sample: nil)
    # root is MASTER's own directory (Master::ROOT); the inventory and the
    # guard live one level up, in the repo the tree shares.
    repo = File.expand_path("..", root)
    {
      apps: SIBLINGS.filter_map { |name| app_entry(repo, name) }.map { |entry| probe_app(entry, probe:) },
      load: load_sample || load_average,
      guard: guard_contract(repo),
    }
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "FleetPanel.read")
    { apps: [], load: nil, guard: nil, error: e.class.name }
  end

  def app_entry(root, name)
    inventory = YAML.safe_load(File.read(File.join(root, APPS_YML)), aliases: true)
    row = inventory.dig("apps", name)
    # .nil?/empty? over .present?: this service stays plain Ruby so the
    # contract suite can load it without Rails.
    return nil unless row.is_a?(Hash) && !row["port"].nil? && !row["port"].to_s.empty?

    { name: name, port: Integer(row["port"]), domain: row["domain"].to_s }
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "FleetPanel.apps")
    nil
  end

  # The probe is injectable so tests and offline hosts can answer without a
  # socket. The real probe asks each sibling's /up on loopback with a short
  # timeout; a refused or slow answer is "down", never an exception.
  def probe_app(entry, probe:)
    answer = if probe
      probe.call(entry)
    else
      http_probe(entry)
    end
    entry.merge(up: answer == true)
  end

  def http_probe(entry)
    uri = URI("http://127.0.0.1:#{entry[:port]}#{HEALTH_PATH}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = PROBE_TIMEOUT_S
    http.read_timeout = PROBE_TIMEOUT_S
    response = http.get(uri.path)
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  # vm23 is OpenBSD (no /proc); Linux dev hosts are. Read whichever the host
  # offers, one-minute average; an unreadable host renders "unknown".
  def load_average
    if File.readable?("/proc/loadavg")
      File.read("/proc/loadavg").to_s.split.first&.to_f
    else
      out = IO.popen(["sysctl", "-n", "vm.loadavg"], err: File::NULL, &:read).to_s
      value = out[/[\d.]+/]
      value&.to_f
    end
  rescue StandardError
    nil
  end

  # The guard's own constants, read once per payload: which services shed
  # first, after how many breaching ticks, and the load levels that count a
  # breach. Parsed, never copied, so the panel cannot drift from the guard.
  def guard_contract(root)
    source = File.read(File.join(root, GUARD_SCRIPT))
    optional = source[/^OPTIONAL="([^"]+)"/, 1]
    return nil unless optional

    {
      shed_order: optional.split,
      shed_strikes: source[/^SHED_STRIKES=\$\{GUARD_SHED_STRIKES:-(\d+)\}/, 1].to_i,
      load_warn: source[/^LOAD_WARN=([\d.]+)/, 1].to_f,
      load_crit: source[/^LOAD_CRIT=([\d.]+)/, 1].to_f,
    }
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "FleetPanel.guard")
    nil
  end
end
