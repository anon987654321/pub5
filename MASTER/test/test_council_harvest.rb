# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"
require_relative "support_council_answer"
require "master"

# The directive this pins (operator, 2026-08-18): a critique is harvested
# automatically into a durable artifact, and the deliberation makes multiple
# proposals per issue, adversarially challenged, before the cherry-pick.
# Four tree-wide critiques ran that day and the one complete deliberation
# survived only as scratchpad scrollback.
class TestCouncilHarvest < Minitest::Test
  FEEDBACK = [
    { persona: "Skeptic", feedback: "apps.yml notes have grown into changelog prose\nmore detail" },
    { persona: "Judge", feedback: "strip dated clauses; git owns history" },
  ].freeze

  def test_harvest_writes_a_durable_artifact_with_all_four_layers
    Dir.mktmpdir do |root|
      path = Master::Review::Council::Harvest.write(
        mode: :general,
        files: ["RAILS/apps.yml"],
        feedback: FEEDBACK,
        ideas: { ideas: ["move notes to git", "add a notes linter"],
                 critiques: ["VERDICT: reject - a linter adds a reader nothing needs"],
                 final: "move notes to git" },
        cherry: ["move notes to git"],
        root:,
      )

      assert File.file?(path), "no harvest written"
      body = File.read(path)
      assert_includes body, "Skeptic"
      assert_includes body, "move notes to git"
      assert_includes body, "adversarial challenges"
      assert_includes body, "cherry-picked"
      latest = File.join(root, ".master", "critiques", "general_latest.md")
      assert File.file?(latest), "no _latest pointer"
      assert_equal body, File.read(latest)
    end
  end

  def test_critique_shares_candidates_before_the_judge_selects_one
    value, prompts = run_critique

    assert_equal :observed, value[:status], value[:reason]
    assert_equal 10, value.dig(:diversity, :distinct)
    assert_operator value.dig(:diversity, :comparison_rounds), :>=, 2
    assert_equal 10, value.dig(:ideas, :ideas).size
    assert_equal 1, value[:cherry_picks].size
    assert_includes value[:cherry_picks].first, "Reuse the registry"
    assert prompts.any? { |prompt| prompt.include?("Prior round") && prompt.include?("candidate 10:") }
    assert prompts.any? { |prompt| prompt.include?("Arbitrate only") && prompt.include?("candidate 10:") }
  end

  def test_incomplete_or_unauthorized_selections_never_become_repairs
    [[1, "KEEP", false, /1\/10 distinct/], [10, "REJECT", false, /rejected or unreviewed/],
     [10, "KEEP", true, /rejected or unreviewed/]].each do |count, verdict, invent, reason|
      value, = run_critique(count:, verdict:, invent:)

      assert_equal :inconclusive, value[:status]
      assert_empty value[:cherry_picks]
      assert_match reason, value[:reason]
    end
  end

  # The prompt was reworded from "Attack each idea ... VERDICT: keep/reject"
  # to an exact-coverage demand. The invariant is unchanged: every supplied
  # candidate gets its own verdict, and both directions are named, because a
  # critique that silently drops a candidate hides a real defect.
  def test_adversarial_challenge_demands_a_verdict_per_idea
    source = File.read(File.join(Master::ROOT, "lib", "review", "council", "ideation.rb"))
    challenge = source[/def critique\(ideas\).*?end\n/m]

    refute_nil challenge, "the adversarial challenge must exist"
    assert_includes challenge, "Attack every candidate separately"
    assert_includes challenge, "exactly one finding for each supplied candidate"
    assert_includes challenge, "Do not omit or invent candidates"
    assert_includes challenge, "KEEP"
    assert_includes challenge, "REJECT:"
  end

  private

  def run_critique(count: 10, verdict: "KEEP", invent: false)
    repairs = ["Reuse the registry", "Freeze the inputs", "Delete the wrapper", "Link two receipts",
               "Partition the batch", "Defer checkout inspection", "Merge the duplicate prompts",
               "Validate at dispatch", "Reuse the stored snapshot", "Limit candidate authors"]
    findings = repairs.first(count).map do |repair|
      { "location" => "MASTER/test/test_council_harvest.rb:1", "evidence" => "The supplied source.",
        "severity" => "warning", "claim" => "The review loses candidate evidence.", "proposed_repair" => repair }
    end
    prompts = Queue.new
    agent = Object.new
    router = Struct.new(:local_models, :local_server_models).new([], ["local:gemma3:4b"])
    agent.define_singleton_method(:model_router) { router }
    agent.define_singleton_method(:ask) { |*| raise "source critique must use the local dispatcher" }
    agent.define_singleton_method(:ask_once) do |prompt, model:, local_only:, **|
      raise "source escaped the local lane" unless local_only && model == "local:gemma3:4b"

      prompts << prompt
      answer = JSON.parse(CouncilAnswer.json)
      answer["position"] = "mixed" if prompt.match?(/"prior_findings"\s*:\s*\[/)
      if prompt.include?(%q{"role": "judge"})
        answer["findings"] = [invent ? findings.first.merge("proposed_repair" => "Invent a new repair") : findings.first]
        answer["position_evidence"] = findings.each_index.map do |index|
          { "location" => "candidate #{index + 1}", "evidence" => "#{index.zero? ? verdict : 'REJECT'}: cite the stated trade-off" }
        end
      else
        answer["findings"] = findings
      end
      JSON.generate(answer)
    end
    council = Master::Review::Council
    critique = council::Critique
    result = Master::Fix::UserSimulation.stub(:candidate_count, 10) do
      source = File.join(Master::ROOT, "lib", "review", "council", "harvest.rb")
      critique.new(mode: :general, agent:, files: [source], harvest: false).run
    end
    assert result.ok?, (result.message if result.err?)
    [result.value!, Array.new(prompts.size) { prompts.pop }]
  end
end
