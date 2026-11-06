#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/config_renderer"

mode = ARGV.shift
unless ARGV.empty? && [nil, "--check", "--write"].include?(mode)
  warn "usage: ruby openbsd/bin/render_configs.rb [--check|--write]"
  exit 64
end

renderer = OpenBSD::ConfigRenderer.new
begin
  if mode == "--write"
    renderer.write!
    puts "openbsd config: generated mirror updated; proven baseline unchanged"
  else
    renderer.check!
    puts "openbsd config: registry, proven fixtures and generated mirror agree"
  end
rescue OpenBSD::ConfigRenderer::Failure, Core::Refusal, KeyError, ArgumentError => e
  warn "openbsd config: FAIL: #{e.message}"
  exit 1
end
