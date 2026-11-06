#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/config_renderer"
require_relative "../../core/core"

mode = ARGV.shift
unless ARGV.empty? && [nil, "--check", "--write"].include?(mode)
  warn "usage: ruby openbsd/bin/render_configs.rb [--check|--write]"
  exit 64
end

if mode == "--write"
  files = OpenBsdRender.generated_files
  manifest = Core::Manifest.new(name: "openbsd-render", verbs: { write: files.keys })
  ledger = Core::Ledger.new(Core::Knobs.fetch("PUB5_LEDGER"))
  world = Core::World.new(manifest:, ledger:)
  files.each { |path, (content, file_mode)| world.write(path, content, mode: file_mode) }
end

diffs = OpenBsdRender.check
if diffs.empty?
  puts "openbsd: registry, proven fixtures and generated mirror agree"
else
  diffs.each { |diff| warn "openbsd: #{diff}" }
  exit 1
end
