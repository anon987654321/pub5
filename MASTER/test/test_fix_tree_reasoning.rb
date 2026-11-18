# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

class TestFixTreeReasoning < Minitest::Test
  Reasoning = Master::Fix::TreeReasoning

  class FakeAgent
    attr_reader :prompts

    def initialize(answer) = (@answer = answer
                              @prompts = [])

    def ask(prompt, **)
      @prompts << prompt
      @answer.is_a?(Proc) ? @answer.call : @answer
    end
  end

  def setup
    @root = Dir.mktmpdir("fix-tree-reasoning")
    %w[lib/a.rb lib/a_helper.rb lonely/only.rb].each do |path|
      FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
      File.write(File.join(@root, path), "x" * 400)
    end
    Open3.capture2e("git", "-C", @root, "init", "-q")
    Open3.capture2e("git", "-C", @root, "add", ".")
  end

  def teardown = FileUtils.remove_entry(@root)

  def test_a_proposal_over_known_paths_is_kept_and_saved
    agent = FakeAgent.new("PROPOSE: merge | lib/a.rb, lib/a_helper.rb | SINGULARITY | one concept split in two\n")
    result = Reasoning.new(agent:, root: @root).call(target: @root)

    assert_predicate result, :answered?
    assert_equal %w[lib/a.rb lib/a_helper.rb], result.proposals.first.paths
    assert_equal "SINGULARITY", result.proposals.first.law
    assert_equal "merge", Reasoning.hints(@root).first["kind"]
    assert_includes agent.prompts.first, "lonely"
  end

  def test_a_proposal_naming_an_unknown_path_is_dropped
    agent = FakeAgent.new(
      "PROPOSE: delete | lib/invented.rb | NONE | not there\nPROPOSE: rename | lonely/only.rb | NONE | clearer\n",
    )
    result = Reasoning.new(agent:, root: @root).call(target: @root)

    assert_equal 1, result.proposals.size
    assert_equal 1, result.dropped
    assert_includes result.summary, "unknown path (lib/invented.rb)"
  end

  def test_look_stage_drop_reasons_are_attached_to_the_existing_event_receipt
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **details| events << [event, details] }
    agent = FakeAgent.new("PROPOSE: delete | lib/invented.rb | NONE | private explanation stays out of the receipt\\n")

    result = Reasoning.new(agent:, root: @root, bus:).call(target: @root)

    assert_equal 1, result.dropped
    event = events.find { |name, _details| name == "fix_loop:tree" }
    refute_nil event
    assert_equal ["unknown path (lib/invented.rb)"], event.last.fetch(:dropped_reasons)
    refute_includes event.last.inspect, "private explanation"
  end

  def test_a_directory_named_with_a_trailing_slash_is_known
    agent = FakeAgent.new("PROPOSE: merge | lib/, lonely/ | NONE | fold the two\n")
    result = Reasoning.new(agent:, root: @root).call(target: @root)

    assert_equal %w[lib lonely], result.proposals.first.paths
  end

  def test_an_unknown_kind_is_dropped
    agent = FakeAgent.new("PROPOSE: vaporise | lib/a.rb | NONE | no\n")
    result = Reasoning.new(agent:, root: @root).call(target: @root)

    assert_empty result.proposals
    assert_equal 1, result.dropped
    assert_includes result.summary, "1 invalid proposal(s) dropped"
  end

  def test_no_model_is_reported_and_does_not_raise
    result = Reasoning.new(agent: Object.new, root: @root).call(target: @root)

    assert_equal :unavailable, result.state
  end

  def test_a_failing_model_is_inconclusive_not_fatal
    agent = FakeAgent.new(-> { raise "lane down" })
    result = Reasoning.new(agent:, root: @root).call(target: @root)

    assert_equal :inconclusive, result.state
    assert_empty result.proposals
  end

  def test_read_only_read_returns_proposals_without_persisting_them
    agent = FakeAgent.new("PROPOSE: merge | lib/a.rb, lib/a_helper.rb | NONE | one concept\n")

    result = Reasoning.new(agent:, root: @root).call(target: @root, persist: false)

    assert_predicate result, :answered?
    assert_equal 1, result.proposals.size
    refute File.exist?(Reasoning.hints_path(@root)), "read-only tree reasoning must not save hints"
    refute Dir.exist?(File.join(@root, ".master")), "read-only tree reasoning must not create state directories"
  end
end
