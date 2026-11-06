# frozen_string_literal: true

require_relative "../test_helper"

# One refusal per World verb: a manifest that does not declare the verb is
# refused, and so is a target the verb's declaration does not cover. Each
# refusal leaves a ledger line and no effect.
class CapabilityTest < Minitest::Test
  include TestHelper

  # Records requests instead of reaching the network.
  class Transport
    attr_reader :calls

    def initialize = @calls = []

    def request(method, url, **options)
      @calls << [method, url, options]
      Core::HTTP::Reply.new(status: 200, headers: {}, body: '{"content":[{"text":"hi"}],"usage":{"input_tokens":3,"output_tokens":1}}')
    end
  end

  VERB_CALLS = {
    read: ->(w) { w.read("notes.txt") },
    write: ->(w) { w.write("notes.txt", "x") },
    render: ->(w) { w.render("page.erb") },
    exec: ->(w) { w.exec("ruby", "-e", "1") },
    git: ->(w) { w.git("status") },
    net: ->(w) { w.net(:get, "https://example.org/") },
    llm: ->(w) { w.llm(provider: "anthropic", model: "m", messages: []) }
  }.freeze

  def test_every_world_verb_is_covered_here
    assert_equal Core::Manifest::VERBS.sort, VERB_CALLS.keys.sort
  end

  VERB_CALLS.each do |verb, call|
    define_method(:"test_#{verb}_refused_when_undeclared") do
      sandbox do |root|
        put(root, "notes.txt", "n")
        put(root, "page.erb", "<%= 1 %>")
        transport = Transport.new
        w = world(root, {}, transport:)
        error = assert_raises(Core::Refusal) { call.call(w) }
        assert_equal verb, error.verb
        assert_match(/does not declare #{verb}/, error.message)
        assert_empty transport.calls
        assert_equal "n", File.read(File.join(root, "notes.txt"))
        assert_equal ["refusal"], w.ledger.entries.map { |e| e["kind"] }
      end
    end
  end

  # Each verb declared, but for something else.
  OTHER_TARGET = { read: ["other/**"], write: ["other/**"], render: ["other/**"], exec: ["git"],
                   git: ["log"], net: ["api.anthropic.com"], llm: ["openai"] }.freeze

  VERB_CALLS.each do |verb, call|
    define_method(:"test_#{verb}_refused_for_an_undeclared_target") do
      sandbox do |root|
        put(root, "notes.txt", "n")
        put(root, "page.erb", "<%= 1 %>")
        transport = Transport.new
        w = world(root, { verb => OTHER_TARGET.fetch(verb) }, transport:)
        error = assert_raises(Core::Refusal) { call.call(w) }
        assert_equal verb, error.verb
        assert_empty transport.calls
      end
    end
  end

  def test_declared_verbs_run_and_land_in_the_ledger
    sandbox do |root|
      put(root, "page.erb", "<%= name %>")
      transport = Transport.new
      providers = { "anthropic" => { "env" => ["ANTHROPIC_API_KEY"], "protocol" => "anthropic", "base" => "https://api.anthropic.com/v1" } }
      verbs = { read: ["out/*"], write: ["out/*"], render: ["*.erb"], exec: ["ruby"], git: ["init"],
                net: ["example.org"], llm: ["anthropic"] }
      w = world(root, verbs, transport:, models: { "providers" => providers }, env: { "ANTHROPIC_API_KEY" => "k" })
      w.write("out/a.txt", "a")
      assert_equal "a", w.read("out/a.txt")
      assert_equal "x", w.render("page.erb", name: "x")
      assert_equal "2\n", w.exec("ruby", "-e", "puts 1 + 1").out
      assert w.git("init", "-q").ok?
      assert_equal 200, w.net(:get, "https://example.org/").status
      assert_equal "hi", w.llm(provider: "anthropic", model: "m", messages: []).text
      assert_equal %w[effect effect effect effect llm], w.ledger.entries.map { |e| e["kind"] }
    end
  end

  def test_paths_cannot_escape_the_root
    sandbox do |root|
      w = world(root, { read: ["**/*"], write: ["**/*"] })
      assert_raises(Core::Refusal) { w.read("../etc/passwd") }
      assert_raises(Core::Refusal) { w.read("/etc/passwd") }
      File.symlink("/etc", File.join(root, "link"))
      assert_raises(Core::Refusal) { w.read("link/passwd") }
      assert_raises(Core::Refusal) { w.write("link/x", "x") }
    end
  end

  def test_protected_paths_refuse_writes_even_when_declared
    sandbox do |root|
      w = world(root, { write: ["**/*"] })
      error = assert_raises(Core::Refusal) { w.write("registry/apps.yml", "x") }
      assert_match(/protected/, error.message)
      refute File.exist?(File.join(root, "registry/apps.yml"))
    end
  end

  # "registry/**" protects the whole tree, not one level of it.
  def test_a_protected_tree_refuses_writes_at_every_depth
    sandbox do |root|
      w = world(root, { write: ["**/*"] })
      assert_raises(Core::Refusal) { w.write("registry/schemas/apps.yml", "x") }
      refute File.exist?(File.join(root, "registry/schemas/apps.yml"))
    end
  end

  def test_only_the_named_generator_writes_a_generated_file
    sandbox do |root|
      generated = { "registry/out.md" => { "by" => "generate" } }
      assert_raises(Core::Refusal) { world(root, { write: ["**/*"] }, generated:).write("registry/out.md", "x") }
      world(root, { write: ["**/*"] }, generated:, name: "generate").write("registry/out.md", "x")
      assert_equal "x", File.read(File.join(root, "registry/out.md"))
    end
  end

  def test_unknown_verbs_are_refused
    sandbox do |root|
      assert_raises(Core::Refusal) { Core::Manifest.new(name: "x", verbs: { delete: ["*"] }, root:, protected_paths: []) }
      manifest = Core::Manifest.new(name: "x", verbs: {}, root:, protected_paths: [])
      assert_raises(Core::Refusal) { manifest.check!(:sudo, "rm") }
    end
  end

  def test_exec_times_out_and_reports_it
    sandbox do |root|
      run = world(root, { exec: ["ruby"] }).exec("ruby", "-e", "sleep 30", timeout: 0.3)
      assert run.timed_out
      refute run.ok?
    end
  end
end
