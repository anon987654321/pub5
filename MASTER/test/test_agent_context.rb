# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "../tools/agent_context"

class TestAgentContext < Minitest::Test
  def test_shell_contract_names_the_runtime_primitives
    text = Operator::AgentContext.shell_contract.join("\n")

    assert_includes text, "zsh"
    assert_includes text, "Master::Io::Exec"
    assert_includes text, "establish the source tree before selecting files"
  end

  def test_fix_context_is_explicitly_executable
    text = Operator::AgentContext.fix_context
    assert_match(/\AMASTER \/fix external-agent contract v\d+$/, text)
    assert_includes text, "The model is the semantic analyst"
    assert_includes text, "No deterministic fixer exists"
  end

  def test_claim_check_map_projects_the_existing_execution_registry
    path = File.join(Operator::AgentContext::MASTER_DIR, "checks", "checks.yml")
    registry = YAML.safe_load_file(path, aliases: false)
    map = Operator::AgentContext.claim_check_map

    assert_equal "MASTER/checks/checks.yml", map.fetch("source")
    assert_equal registry.size, map.fetch("entry_count")
    assert_equal "ruby MASTER/checks/runner.rb --all", map.fetch("execution_command")
    assert_includes map.fetch("interpretation"), "not evidence"

    entries = map.fetch("entries").to_h { |entry| [entry.fetch("check"), entry] }
    assert_equal registry.keys.map(&:to_s).sort, entries.keys.sort
    registry.each do |name, row|
      entry = entries.fetch(name.to_s)
      expected_claim = row["pass"].to_s.strip
      assert_equal(expected_claim.empty? ? nil : expected_claim, entry["claim"])
      assert_equal(expected_claim.empty? ? "not_declared" : "declared", entry["claim_status"])
      assert_equal Array(row["needs"]).map(&:to_s), entry["needs"]
      assert_equal row["covered_by"]&.to_s, entry["covered_by"]
      expected_kind = row.key?("script") ? "script" : "class"
      assert_equal expected_kind, entry.dig("instrument", "kind")
      assert_equal row["script"], entry.dig("instrument", "path") if row.key?("script")
      assert_equal row["class"], entry.dig("instrument", "class") if row.key?("class")
      assert_equal row["require"], entry.dig("instrument", "require") if row["require"]
      assert_equal row["gap"], entry["gap"] if row["gap"].is_a?(Hash)
    end
  end

  def test_json_exposes_the_claim_check_map_only_on_request
    refute Operator::AgentContext.session_json.key?("claim_check_map")
    assert_equal Operator::AgentContext.claim_check_map,
                 Operator::AgentContext.session_json(checks: true).fetch("claim_check_map")
  end

  def test_tree_mode_skips_runtime_noise
    Dir.mktmpdir("agent-tree") do |root|
      FileUtils.mkdir_p(File.join(root, "src", "nested"))
      FileUtils.mkdir_p(File.join(root, "node_modules", "noise"))
      File.write(File.join(root, "src", "main.rb"), "puts 1\n")
      File.write(File.join(root, "src", "nested", "deep.rb"), "puts 2\n")

      output = Operator::AgentContext.render_tree(root:, max_depth: 4, max_entries: 10)

      assert_includes output, "src/"
      assert_includes output, "main.rb"
      assert_includes output, "deep.rb"
      refute_includes output.lines.grep_v(/\Askips:/).join, "node_modules"
    end
  end

  def test_tree_mode_respects_the_entry_limit
    Dir.mktmpdir("agent-tree") do |root|
      10.times { |i| File.write(File.join(root, "file#{i}.rb"), "puts #{i}\n") }

      output = Operator::AgentContext.render_tree(root:, max_depth: 4, max_entries: 3)

      assert_includes output, "entries shown: 3"
      assert_includes output, "max entries reached"
    end
  end
end
