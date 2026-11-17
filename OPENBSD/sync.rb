#!/usr/bin/env ruby
# frozen_string_literal: true
# Mirror live VPS config into OPENBSD/ with secret redaction.
# Run on VPS: doas ruby ~/pub5/OPENBSD/sync.rb

require "fileutils"
require_relative "checks/config_drift_check"
require_relative "lib/secret_redaction"

OPENBSD_ROOT = File.dirname(MIRROR)

# Read every tracked literal filesystem file back into the matching mirror path.
# The only non-mirror source is a redacted developer shell snapshot for review;
# it must never be copied over /home/dev/.zshrc. Root crontab is reconciled by
# OPERATOR.sh. DNSSEC signatures/private keys remain runtime state, not payloads.

SOURCES = (
  VERBATIM.to_a +
  [["data/dev.zshrc.redacted", "/home/dev/.zshrc"]]
).freeze

def redact(body)
  SecretRedaction.redact(body)
end

# A Mac has its own /etc/pf.conf and /etc/ssh/sshd_config, and copying those
# over the vm23 mirror is a silent overwrite.
unless on_vps?
  warn "sync: refused - run on vm23 as root (doas ruby OPENBSD/sync.rb); this machine's /etc is not the box's"
  exit 2
end

mirrored = []
skipped = []
refused = []
SOURCES.each do |repo_rel, live_path|
  unless File.exist?(live_path)
    skipped << live_path
    next
  end
  body = File.read(live_path, encoding: "UTF-8", invalid: :replace, undef: :replace)
  # Refuse before writing: a mirrored file is the drift check's comparison
  # source, so a secret the patterns never learned would sit in git until
  # someone reads it. A refusal surfaces the line here instead.
  if (left = SecretRedaction.residue(body)).any?
    refused << live_path
    warn "sync: refused #{live_path} - secret-shaped lines survived redaction:"
    left.each { |line| warn "  #{line}" }
    warn "  extend lib/secret_redaction.rb patterns if these are benign"
    next
  end
  dest = repo_rel.start_with?("data/") ? File.join(OPENBSD_ROOT, repo_rel) : File.join(MIRROR, repo_rel)
  FileUtils.mkdir_p(File.dirname(dest))
  File.write(dest, redact(body))
  mirrored << live_path
end

puts "mirrored #{mirrored.size}:"
mirrored.each { |p| puts "  #{p}" }
if skipped.any?
  puts "skipped (not present): #{skipped.size}"
  skipped.each { |p| puts "  #{p}" }
end
exit 3 if refused.any?
