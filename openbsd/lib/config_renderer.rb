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
  GENERATED = File.join(ROOT, "openbsd", "etc")

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

  # rc.d: one script per app, moved row for row into the registry (comments
  # included - each app's incident prose lives in its own script).
  def rc_script(name)
    rc_scripts.fetch(name)["rows"].map { |row| row["line"] }.join("\n") << "\n"
  end

  def rc_scripts = registry["rc"]["scripts"]

  def rc = rc_scripts.keys.sort.to_h { |name| [name, rc_script(name)] }

  # The app-name tokens the skeleton gate substitutes, so per-app facts may
  # not hide a copy from being recognised as one.
  APP_TOKENS = /amber|brgen|bsdports|mrdamascy/i
  PORT_TOKEN = /\b\d{5}\b/

  # The tokenized code rows of one script: the shape's shared skeleton. Only
  # daemon_flags is per-app (each app's export list is a decision), so the
  # rest cannot drift apart in many silently different copies.
  def skeleton(rows)
    rows.select { |row| row["kind"] == "code" }
        .map { |row| row["line"].gsub(APP_TOKENS, "APP").gsub(PORT_TOKEN, "PORT") }
        .reject { |line| line.start_with?("daemon_flags=") }
  end

  # rc.d gates, same shape as consistency(): the caller passes the registry
  # and the serving view, and gets back named diffs - nothing skips.
  def rc_consistency(scripts, apps)
    diffs = []

    # Serving facts are web-app gates: the jobs, master and irc scripts bind
    # no port and serve no app of their own.
    scripts.each do |name, script|
      next unless %w[falcon puma].include?(script["shape"])

      diffs.concat(rc_facts(name, script, apps))
    end
    scripts.keys.group_by { |name| scripts[name]["shape"] }.each_value do |names|
      names.sort.each_cons(2) do |a, b|
        next if skeleton(scripts[a]["rows"]) == skeleton(scripts[b]["rows"])

        diffs << "rc: #{a} and #{b} are both #{scripts[a]["shape"]} but their code skeletons diverge"
      end
    end
    diffs
  end

  # Serving facts of one script, checked against the app registry.
  def rc_facts(name, script, apps)
    diffs = []
    app = apps[name]
    port_row = script["rows"].find { |r| r["line"] =~ /\APORT=(\d+)\z/ }

    diffs << "rc: #{name} serves no registered app" unless app
    diffs << "rc: #{name} carries no PORT line" unless port_row
    return diffs if app.nil? || port_row.nil?

    port = Regexp.last_match(1).to_i
    unless app["port"] == port
      diffs << "rc: #{name} PORT=#{port} disagrees with the registry port #{app["port"]}"
    end
    diffs << "rc: #{name} does not run as its own user" unless script["rows"].find { |r| r["line"] =~ /\Adaemon_user="#{name}"\z/ }
    diffs << "rc: #{name} does not exec from /home/#{name}/app" unless script["rows"].find { |r| r["line"] == "APP_DIR=/home/#{name}/app" }
    diffs << "rc: #{name} does not source /etc/#{name}.env" unless script["rows"].any? { |r| r["line"].include?("/etc/#{name}.env") }
    diffs
  end

  # The gate: the registry must generate the proven bytes, and the two
  # registries must agree. Nothing here skips: a missing host match, a port
  # disagreement, or a byte difference is a named diff.
  def generated_files
    files = {
      "openbsd/etc/relayd.conf" => [relayd, 0o644],
      "openbsd/etc/pf.conf" => [pf, 0o644]
    }
    rc.each do |name, content|
      files[File.join("openbsd", "etc", "rc.d", name)] = [content, 0o755]
    end
    files
  end

  def check(dir: PROVEN, generated: GENERATED)
    diffs = []
    rendered = { "relayd.conf" => relayd, "pf.conf" => pf }

    directories = { proven: dir }
    directories[:generated] = generated unless generated.nil?
    directories.each do |label, base|
      rendered.each do |name, text|
        path = File.join(base, name)
        if File.file?(path) && !File.symlink?(path)
          diffs << "#{label}/#{name}: differs from registry" unless File.binread(path) == text
        else
          diffs << "#{label}/#{name}: missing regular file at #{path}"
        end
      end

      expected_scripts = rc.keys.sort
      scripts_dir = File.join(base, "rc.d")
      actual_scripts = if File.directory?(scripts_dir) && !File.symlink?(scripts_dir)
                         Dir.children(scripts_dir).select do |name|
                           path = File.join(scripts_dir, name)
                           File.file?(path) && !File.symlink?(path)
                         end.sort
                       else
                         []
                       end
      unless actual_scripts == expected_scripts
        diffs << "#{label}/rc.d: expected #{expected_scripts.join(", ")}, found #{actual_scripts.join(", ")}"
      end

      rc.each do |name, text|
        path = File.join(scripts_dir, name)
        if File.file?(path) && !File.symlink?(path)
          diffs << "#{label}/rc.d/#{name}: differs from registry" unless File.binread(path) == text
        else
          diffs << "#{label}/rc.d/#{name}: missing regular file at #{path}"
        end
      end
    end

    diffs.concat(consistency(configured_apps, rendered["relayd.conf"]))
    diffs.concat(rc_consistency(rc_scripts, configured_apps))
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
