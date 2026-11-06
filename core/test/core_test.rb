# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "json"
require "yaml"
require "pub5"

class CoreTest < Minitest::Test
  def with_root(&block) = Dir.mktmpdir("pub5-core", &block)

  def capabilities(root, rows)
    path = File.join(root, "plugin.yml")
    File.write(path, { "schema" => 1, "capabilities" => rows }.to_yaml)
    Pub5::Core::CapabilityManifest.load(path, root: root)
  end

  def test_undeclared_verb_is_refused
    with_root { |root| assert_raises(Pub5::Core::Denied) { capabilities(root, [{ "verb" => "read" }]).allow!("write") } }
  end

  def test_path_escape_and_symlink_are_refused
    with_root do |root|
      guard = Pub5::Core::SafePath.new(root)
      assert_raises(Pub5::Core::Denied) { guard.resolve("../outside") }
      File.write(File.join(root, "target"), "ok")
      File.symlink(File.join(root, "target"), File.join(root, "link"))
      assert_raises(Pub5::Core::Denied) { guard.resolve("link") }
    end
  end

  def test_atomic_writer_refuses_protected_registry
    with_root do |root|
      cap = capabilities(root, [{ "verb" => "write", "paths" => ["**/*"] }])
      writer = Pub5::Core::AtomicWriter.new(root: root, capabilities: cap)
      assert_raises(Pub5::Core::Denied) { writer.write("registry/models.yml", "tamper") }
    end
  end

  def test_world_invokes_only_granted_adapter
    with_root do |root|
      cap = capabilities(root, [{ "verb" => "llm" }])
      writer = Object.new
      http = Object.new
      world = Pub5::Core::World.new(root: root, capabilities: cap, writer: writer, http: http, adapters: { llm: ->(input) { "ok: #{input}" } })
      assert_equal "ok: prompt", world.llm("prompt")
      assert_raises(Pub5::Core::Denied) { world.git("status") }
    end
  end

  def test_ledger_is_append_only_jsonl
    with_root do |root|
      path = File.join(root, "state", "events.jsonl")
      ledger = Pub5::Core::Ledger.new(path)
      ledger.append("event" => "started")
      ledger.append("event" => "finished")
      rows = File.readlines(path).map { |line| JSON.parse(line) }
      assert_equal %w[started finished], rows.map { |row| row.fetch("event") }
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_registry_rejects_yaml_aliases
    with_root do |root|
      path = File.join(root, "registry.yml")
      File.write(path, "schema: 1\nbase: &v 1\ncopy: *v\n")
      assert_raises(Pub5::Core::InvalidRegistry) { Pub5::Core::Registry.load(path) }
    end
  end

  def test_http_client_refuses_http_and_unknown_hosts
    client = Pub5::Core::HttpClient.new(allowed_hosts: ["example.com"])
    assert_raises(Pub5::Core::Denied) { client.get("http://example.com/data") }
    assert_raises(Pub5::Core::Denied) { client.get("https://other.example/data") }
  end
end
