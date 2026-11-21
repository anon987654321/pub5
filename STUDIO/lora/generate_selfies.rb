#!/usr/bin/env ruby
# frozen_string_literal: true

# Canonical STUDIO selfie entrypoint. With no arguments, render the six-take
# series for all three consented subjects through the existing photograph lane.
require "rbconfig"

script = File.expand_path("photograph.rb", __dir__)
arguments = ARGV.empty? ? %w[--all-subjects --count 6] : ARGV
exec(RbConfig.ruby, script, *arguments)
