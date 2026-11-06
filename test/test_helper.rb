# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../core/core"

module TestHelper
  # A throwaway root with a manifest over it; protected paths are given
  # explicitly so a test never depends on the live registry/paths.yml.
  def sandbox
    Dir.mktmpdir("pub5-test") { |dir| yield File.realpath(dir) }
  end

  def knobs(env = {})
    Core::Knobs.new(Core::Registry.load(:knobs).fetch("knobs"), env:)
  end

  def world(root, verbs, protected_paths: ["registry/**"], generated: {}, name: "test", env: {}, **options)
    manifest = Core::Manifest.new(name:, verbs:, root:, protected_paths:, generated:)
    Core::World.new(manifest:, ledger: Core::Ledger.new(File.join(root, "log/ledger.jsonl")), knobs: knobs(env), **options)
  end

  # Fixture files go through the one atomic write, like everything else.
  def put(root, relative, text) = Core::Atomic.write(File.join(root, relative), text)
end
