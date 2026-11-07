# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../tools/cli_contracts"

# The route-contract suite's rules, for the CLI: record from a running
# entrypoint in this checkout, check against any other, and never run a
# command whose answer is work. --help is the only command invoked.
class TestCliContracts < Minitest::Test
  OPERATOR_HELP = <<~TEXT
    help0 at master0: operator - repo-wide operator surface

    help0 at master0: Usage:
    help0: bin/operator check [--scan-only] [--only=a,b] [--tree=T]
    help0: bin/operator lint
    help0: bin/operator tree-weight
  TEXT

  MASTER_HELP = <<~TEXT
    help0 at master0: master - instruct the MASTER runtime with the whole repo in scope

    help0 at master0: Usage:
    help0: bin/master core [--root PATH] [--max-turns N] GOAL
    help0: bin/master "<instruction>"
    help0: bin/master replay <sequence>
  TEXT

  # minitest/mock is not installed here; swap the module functions.
  def with_run(answers)
    original = CliContracts.method(:run)
    CliContracts.define_singleton_method(:run) { |root, path| answers.fetch(path, [0, "", ""]) }
    yield
  ensure
    CliContracts.define_singleton_method(:run, original)
  end

  def answers
    { "MASTER/bin/master" => [0, MASTER_HELP, ""],
      "MASTER/bin/operator" => [2, "", OPERATOR_HELP] }
  end

  def test_a_contract_records_the_answered_stream_whichever_pipe_it_used
    with_run(answers) do
      row = CliContracts.contract("/tmp", "MASTER/bin/operator")

      assert_equal 2, row["exit"]
      assert_equal "operator - repo-wide operator surface", row["head"]
      assert_equal %w[check lint tree-weight], row["tokens"]
      assert_match(/\A[0-9a-f]{64}\z/, row["digest"])
    end
  end

  def test_the_help_tag_prefix_is_stripped_from_head_and_tokens
    with_run(answers) do
      row = CliContracts.contract("/tmp", "MASTER/bin/master")

      assert_equal "master - instruct the MASTER runtime with the whole repo in scope", row["head"]
      assert_includes row["tokens"], "core"
      assert_includes row["tokens"], "replay"
    end
  end

  def test_digits_are_normalized_so_a_host_version_cannot_churn_the_digest
    digests = ["help0 at master0: master - v4.0.5\nhelp0: bin/master core\n",
               "help0 at master0: master - v3.4.9\nhelp0: bin/master core\n"].map do |help|
      with_run("MASTER/bin/master" => [0, help, ""], "MASTER/bin/operator" => [2, "", OPERATOR_HELP]) do
        CliContracts.contract("/tmp", "MASTER/bin/master")["digest"]
      end
    end

    assert_equal digests.first, digests.last
  end

  # check()'s filter_map has already been proved by the LoadError test below;
  # what this pins is compare(): identical rows answer nil, not a truthy blank,
  # and a difference names the field it moved.
  def test_compare_silences_when_rows_agree_and_names_the_field_when_they_differ
    want = { "exit" => 2, "head" => "operator", "tokens" => %w[check], "digest" => "a0" }

    assert_nil CliContracts.compare(want, want.dup.merge("digest" => "a0", "head" => "operator"))
    assert_equal 'head: "operator" -> "readme"',
                 CliContracts.compare(want, want.merge("head" => "readme"))
  end

  # A target with no entrypoint answers the loader's LoadError; that is exactly
  # how pub5 says it does not carry this surface yet, so the contract surfaces
  # the loader's words, not a silent skip.
  def test_check_refuses_a_path_the_target_lacks_with_the_loader_error_not_silence
    missing = { "MASTER/bin/master" => [1, "", "ruby: No such file or directory -- MASTER/bin/master (LoadError)"],
                "MASTER/bin/operator" => [1, "", "ruby: No such file or directory -- MASTER/bin/operator (LoadError)"] }
    with_run(missing) do
      diffs = CliContracts.check("/no-such-root")

      assert_equal 2, diffs.size
      assert diffs.first(2).all? { |_path, detail| detail.match?(/LoadError/) }
    end
  end

  # The same shape at the port's own layout: pub5 flattens MASTER/bin/* onto
  # bin/*, so resolving finds the root entrypoint, the diff keeps the recorded
  # contract as what was wanted, and the detail is labelled with the path the
  # answer came from - so a tree that flattened its bin answers a diff about
  # the surface, not a loader error about a path that never existed.
  # (A spelling-only probe cannot run here: APFS tmpdirs are case-insensitive,
  # so MASTER/x and master/x match the same file.)
  def test_check_resolves_the_flattened_entrypoint_and_labels_the_found_path
    Dir.mktmpdir do |root|
      require "fileutils"
      FileUtils.mkdir_p(File.join(root, "bin"))
      File.write(File.join(root, "bin", "master"), "#!/usr/bin/env ruby\n")
      with_run("bin/master" => [0, "master - the port's answer", ""]) do
        diffs = CliContracts.check(root)

        master = diffs.to_h.fetch("MASTER/bin/master")
        assert master.start_with?("bin/master: "),
               "detail must name the resolved path (got: #{master[0, 40]})"
        diffs.to_h.fetch("MASTER/bin/operator")
      end
    end
  end

  # One real anchor: the recorded answers come from these two entrypoints,
  # and this is what a --help answer costs. The contract holds without it.
  def test_the_recorded_contract_matches_this_checkout
    skip if ENV["MASTER_SKIP_LIVE"]

    diffs = CliContracts.check(CliContracts::ROOT)

    assert_empty diffs, diffs.first(2).to_s
  end
end
