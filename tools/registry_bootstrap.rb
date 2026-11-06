#!/usr/bin/env ruby
# frozen_string_literal: true

# The registry bootstrap: one transform from the proven configs
# (openbsd/proven/relayd.conf, proven/pf.conf) into
# registry/openbsd.yml, run once so the proven comment prose - which
# carries behaviour documentation - moves into the registry byte for
# byte, with no hand transcription between. registry/apps.yml is not this
# script's output: the ported app registry (commit 2fb928c, from pub4
# 94cc874ad6) is the source for app facts, and this script only checks
# its serving facts against what the proven configs actually carry.
#
# After this run, the registry is the source: edits land there and the
# renderer reproduces the configs from it. Re-run this script only when
# a newly proven config replaces the fixtures, and review the diff of the
# registry it writes like any generated-output diff.
#
# Ported from pub4 e42dc7006c (OPENBSD/etc/relayd.conf, etc/pf.conf).

require "yaml"
require_relative "../core/core"

ROOT = File.expand_path("..", __dir__)
PROVEN = File.join(ROOT, "openbsd", "proven")

# --- relayd.conf -> registry structure ------------------------------------

text = File.read(File.join(PROVEN, "relayd.conf"))
lines = text.lines(chomp: true)

# Preamble: top lines until the first blank.
blank = lines.index("")
abort "bootstrap: no blank before the tables" unless blank
prelude = lines[0...blank]
# Tables from the first section until the protocol block.
proto_start = lines.index { |l| l.start_with?('http protocol "https_proxy" {') }
abort "bootstrap: relayd protocol block not found" unless proto_start
proto_end = lines.index { |l| l.strip == "}" && lines.index(l) > proto_start }
abort "bootstrap: relayd protocol close not found" unless proto_end

tables = lines[blank...proto_start].grep(/\Atable <(\w+)> \{ 127\.0\.0\.1 \}\z/) {
  Regexp.last_match(1)
}
abort "bootstrap: no tables found" if tables.empty?

# Inside the protocol block: entries are an optional comment block plus the
# directive it documents. The config indents inside the block, so matching
# strips the leading space first.
entries = []
notes = []
lines[(proto_start + 1)...proto_end].each do |line|
  plain = line.lstrip
  case plain
  when /\A#/ then notes << plain
  when /\A\z/ then entries << { "kind" => "blank" }
  else
    kind = if plain =~ /\Atls keypair /
             "keypair"
           elsif plain.start_with?("match")
             "match"
           else
             "directive"
           end
    entries << { "kind" => kind, "line" => plain, "notes" => notes }
    notes = []
  end
end
abort "bootstrap: stray comment in the protocol block" unless notes.empty?

# After the protocol block: the retired-brand comment block, then the relay.
relay_start = lines.index { |l| l.start_with?('relay "https_in" {') }
abort "bootstrap: relay block not found" unless relay_start
relay_body = lines[(relay_start + 1)...-1] # up to the file's closing brace
relay_notes = lines[(proto_end + 1)...relay_start].map(&:lstrip).grep(/\A#/)
# Comments inside the relay block document the listen line (the backlog note).
first_body = relay_body.index { |l| !l.lstrip.start_with?("#") }
abort "bootstrap: relay block is only comments" unless first_body
inner_notes = relay_body[0...first_body].map(&:lstrip).grep(/\A#/)
relay_body = relay_body[first_body..]
forwards = relay_body.filter_map do |line|
  next unless line =~ /\A\s*forward to <(\w+)> port (\d+) check http "(.+)" code (\d+)\z/

  { "app" => Regexp.last_match(1), "port" => Regexp.last_match(2).to_i,
    "path" => Regexp.last_match(3), "code" => Regexp.last_match(4).to_i }
end
listen = relay_body.find { |l| l.lstrip.start_with?("listen on") }
protocol_name = relay_body.find { |l| l.lstrip.start_with?("protocol ") }

# Host matches: which host routes to which table, in the config's order.
hosts = Hash.new { |h, k| h[k] = [] }
entries.each do |entry|
  next unless entry["kind"] == "match" && entry["line"] =~ /\Amatch request header "Host" value "([^"]+)" forward to <(\w+)>\z/

  hosts[Regexp.last_match(2)] << Regexp.last_match(1)
end

# The ported app registry supplies the app-facing facts; the serving ports
# must agree.
ported = Core::Registry.load(:apps)["apps"]
ports = ported.to_h { |name, app| [name, app["port"].to_i] }
domains = ported.to_h { |name, app| [name, app["domain"]] }
tables.each do |name|
  abort "bootstrap: table <#{name}> names no ported app" unless ports[name]
end
ports.each do |name, port|
  abort "bootstrap: ported app #{name} has no relayd table" unless tables.include?(name)
  unless forwards.find { |f| f["app"] == name && f["port"] == port }
    abort "bootstrap: no relayd forward for #{name} on #{port}"
  end
end

openbsd_registry = {
  "schema" => 1,
  "concern" => "openbsd",
  "note" => "The OPENBSD serving policy: relayd and pf generated from these" \
            " rows, byte-checked against openbsd/proven/*.conf. Each entry's" \
            " notes are the proven config's own comments, moved verbatim.",
  "relayd" => {
    "prelude" => prelude,
    "tables" => tables,
    "protocol" => { "header" => lines[proto_start], "entries" => entries },
    "relay" => {
      "header" => lines[relay_start],
      "notes" => relay_notes,
      "inner_notes" => inner_notes,
      "listen" => listen.lstrip,
      "protocol" => protocol_name.lstrip,
      "forwards" => forwards,
    },
  },
}

# --- pf.conf -> registry structure ------------------------------------------

pf_raw = File.read(File.join(PROVEN, "pf.conf")).lines(chomp: true)
# The joined line reads one rule per row; the raw span preserves the config's
# own wrapping so the renderer reproduces the proven file byte for byte.
pf_spans = pf_raw.each_with_object([]) do |line, acc|
  if acc.last && acc.last["pending"]
    acc.last["raw"] << line
    acc.last["line"] = "#{acc.last["line"][0..-2].rstrip} #{line.lstrip}"
    acc.last["pending"] = line.end_with?("\\")
  else
    acc << { "raw" => [line], "line" => line, "pending" => line.end_with?("\\") }
  end
end

pf_rules = []
pf_vars = {}
pf_notes = []
pf_spans.each do |span|
  line = span["line"]
  case line
  when /\A#/ then pf_notes << line
  when /\A\z/ then pf_rules << { "kind" => "blank" }
  when /\A(\w+) = "(.+)"\z/
    pf_vars[Regexp.last_match(1)] = { "value" => Regexp.last_match(2), "notes" => pf_notes, "raw" => span["raw"] }
    pf_notes = []
  when /\Atable <bruteforce> persist\z/
    pf_rules << { "kind" => "table", "line" => line, "notes" => pf_notes, "raw" => span["raw"] }
    pf_notes = []
  when /\Aset /, /\Amatch /, /\Aantispoof /, /\Ablock /, /\Apass /, /\Aanchor /
    pf_rules << { "kind" => "rule", "line" => line, "notes" => pf_notes, "raw" => span["raw"] }
    pf_notes = []
  else
    abort "bootstrap: pf line not understood as var, rule or comment: #{line}"
  end
end
abort "bootstrap: stray pf comments" unless pf_notes.empty?

openbsd_registry["pf"] = { "vars" => pf_vars, "rules" => pf_rules }

# --- rc.d -> registry structure ---------------------------------------------
#
# Every script moves row for row (comments included - they carry the proven
# incident prose). The per-script code skeletons are not compared here: the
# renderer's check() enforces that all falcon scripts (and all jobs scripts)
# share one tokenized skeleton, which is the template guarantee.

SRC = Dir.children(File.join(PROVEN, "rc.d")).sort
rc_scripts = SRC.to_h do |name|
  rows = File.readlines(File.join(PROVEN, "rc.d", name), chomp: true).map do |line|
    kind = if line.empty? then "blank"
           elsif line.start_with?("#") then "comment"
           else "code"
           end
    { "kind" => kind, "line" => line }
  end
  shape = if name.end_with?("_jobs") then "jobs"
          elsif name == "master" then "master"
          elsif name == "irc_gateway" then "irc"
          elsif rows.any? { |r| r["line"].include?("falcon serve") } then "falcon"
          elsif rows.any? { |r| r["line"].include?("puma") } then "puma"
          else
            abort "bootstrap: #{name} does not read as falcon or puma"
          end
  [name, { "shape" => shape, "rows" => rows }]
end

# Web scripts must agree with the ported app registry on the serving port.
rc_scripts.each do |name, script|
  next unless %w[falcon puma].include?(script["shape"])
  app = name
  row = script["rows"].find { |r| r["line"] =~ /\APORT=(\d+)\z/ }
  abort "bootstrap: #{name} carries no PORT line" unless row
  port = Regexp.last_match(1).to_i
  unless port == ports[app]
    abort "bootstrap: #{name} PORT=#{port} disagrees with the registry port #{ports[app]}"
  end
end

openbsd_registry["rc"] = {
  "note" => "rc.d scripts moved row for row (comments included). The" \
            " renderer checks: bytes against proven, serving facts against" \
            " the app registry ports, and one shared tokenized code skeleton" \
            " per shape - the scripts are generated, not maintained, in four" \
            " copies.",
  "scripts" => rc_scripts,
}

Core::Atomic.write(File.join(ROOT, "registry", "openbsd.yml"), YAML.dump(openbsd_registry))
puts "registry/openbsd.yml: #{entries.size} relayd protocol entries, #{relay_notes.size} relay notes, #{pf_rules.size} pf rules, #{pf_vars.size} vars, #{rc_scripts.size} rc.d scripts"
