# frozen_string_literal: true

# The OPENBSD config generator: relayd.conf and pf.conf reproduced from the
# registry (registry/apps.yml, registry/openbsd.yml) and byte-checked against
# the production-proven configs kept verbatim in openbsd/proven/ (pub5
# PLAN.md section 3 keeps them verbatim; section 15's Phase 2 gate is this
# diff-check). Each registry row's notes carry the proven config's own
# commentary, so rendering reproduces the file whole - comments included,
# because there the behaviour decisions live.
#
#   ruby bin/openbsd check    # exit 1 with named diffs, or a quiet pass
#   ruby bin/openbsd render   # print the generated configs to stdout

require_relative "../../core/core"

module OpenBsdRender
  ROOT = File.expand_path("../..", __dir__)
  PROVEN = File.join(ROOT, "openbsd", "proven")

  module_function

  # Registry reads go through Core::Registry - schema-checked, deep-frozen,
  # refused when the schema is missing or a row drifted from it.
  def registry = Core::Registry.load(:openbsd)

  def apps = Core::Registry.load(:apps)

  # The serving view of the ported app registry: what relayd needs per app,
  # derived from pub4's own schema - port, domain, and the hosts the app
  # answers (its domain, www., and the vertical hosts under mobile/).
  def configured_apps
    @configured_apps ||= apps["apps"].to_h do |name, row|
      verticals = (row["mobile"] || {}).values.select { |v| v.is_a?(Hash) && v["host"] }
      hosts = [row["domain"], "www.#{row["domain"]}"] +
              verticals.map { |v| v["host"] }
      [name, { "port" => row["port"], "domain" => row["domain"], "hosts" => hosts }]
    end
  end

  def relayd
    r = registry["relayd"]
    out = []

    out.concat(r["prelude"])
    out << ""
    r["tables"].each { |name| out << "table <#{name}> { 127.0.0.1 }" }
    out << ""
    out << r["protocol"]["header"]
    r["protocol"]["entries"].each do |entry|
      if entry["kind"] == "blank"
        out << ""
      else
        out.concat(entry["notes"].map { |note| "  #{note}" })
        out << "  #{entry["line"]}"
      end
    end
    out << "}"
    out << ""
    out.concat(r["relay"]["notes"])
    out << ""
    out << r["relay"]["header"]
    out.concat(r["relay"]["inner_notes"].map { |note| "  #{note}" })
    out << "  #{r["relay"]["listen"]}"
    out << "  #{r["relay"]["protocol"]}"
    r["relay"]["forwards"].each do |forward|
      out << "  forward to <#{forward["app"]}> port #{forward["port"]} " \
             "check http \"#{forward["path"]}\" code #{forward["code"]}"
    end
    out << "}"
    out.join("\n") << "\n"
  end

  def pf
    rules = registry["pf"]
    out = []

    rules["vars"].each do |_name, var|
      out.concat(var["notes"])
      out.concat(var["raw"])
    end
    rules["rules"].each do |rule|
      if rule["kind"] == "blank"
        out << ""
      else
        out.concat(rule["notes"])
        out.concat(rule["raw"])
      end
    end
    out.join("\n") << "\n"
  end

  # The gate: the registry must generate the proven bytes, and the two
  # registries must agree. Nothing here skips: a missing host match, a port
  # disagreement, or a byte difference is a named diff.
  def check(dir: PROVEN)
    diffs = []

    rendered = { "relayd.conf" => relayd, "pf.conf" => pf }
    rendered.each do |name, text|
      path = File.join(dir, name)
      if File.file?(path)
        diffs << "#{name}: differs from proven" unless File.read(path) == text
      else
        diffs << "#{name}: no proven fixture at #{path}"
      end
    end

    diffs.concat(consistency(configured_apps, rendered["relayd.conf"]))
    diffs
  end

  def consistency(configured, relayd_text)
    diffs = []

    registry["relayd"]["tables"].each do |name|
      diffs << "relayd: table <#{name}> names no registered app" unless configured[name]
    end
    configured.each do |name, app|
      unless registry["relayd"]["relay"]["forwards"].find { |f| f["app"] == name && f["port"] == app["port"] }
        diffs << "relayd: no forward serves #{name} on #{app["port"]}"
      end
      unless relayd_text.include?("tls keypair \"#{app["domain"]}\"")
        diffs << "relayd: no tls keypair for #{name}'s domain #{app["domain"]}"
      end
    end
    # Every Host match must name a host the registry says this app answers,
    # so no match line can drift into serving something unrecorded.
    registry["relayd"]["protocol"]["entries"].each do |entry|
      next unless entry["kind"] == "match" && entry["line"] =~ /\Amatch request header "Host" value "([^"]+)" forward to <(\w+)>\z/

      host, app = Regexp.last_match(1), Regexp.last_match(2)
      unless configured[app] && configured[app]["hosts"].include?(host)
        diffs << "relayd: Host #{host} routes to #{app}, but the registry does not say it answers there"
      end
    end
    registry["relayd"]["relay"]["forwards"].each do |forward|
      next if configured[forward["app"]]

      diffs << "relayd: forward serves unknown app #{forward["app"]}"
    end
    diffs
  end
end
