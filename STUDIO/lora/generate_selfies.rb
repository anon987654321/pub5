#!/usr/bin/env ruby
# frozen_string_literal: true

# Canonical STUDIO selfie entrypoint. With no arguments, render the four-take
# series for all three consented subjects through the existing photograph lane.
require "rbconfig"
require_relative "../replicate/subprocess"

script = File.expand_path("photograph.rb", __dir__)
arguments = ARGV.empty? ? %w[--all-subjects --count 4] : ARGV
exec(Studio::Subprocess.environment, RbConfig.ruby, script, *arguments)
