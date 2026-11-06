# frozen_string_literal: true

# Ruby 3.4.9 is the vm23 runtime; Bundler resolves the stable Rails 8.1 line.

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
