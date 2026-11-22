#!/usr/bin/env ruby
# frozen_string_literal: true

# Canonical STUDIO selfie entrypoint. With no arguments, preflight each subject
# independently, then render four takes only for subjects whose own consent and
# pinned-model checks pass. A blocked subject does not block the others.
require "rbconfig"
require_relative "../replicate/subprocess"

script = File.expand_path("photograph.rb", __dir__)
arguments = ARGV.empty? ? %w[--all-subjects --count 4] : ARGV
exec(Studio::Subprocess.environment, RbConfig.ruby, script, *arguments)
