# frozen_string_literal: true

require_relative "fix_helper"

# `bin/master fix` end to end on a fixture repository, as a separate
# process, with a stubbed claude: it repairs a seeded finding and commits it
# in the house format, puts back the repair the commit hook refuses, and
# skips the protected file before any model is asked. The stub sysctl holds
# the host's load at 0.5 so the model gate's load wait does not pace a test.
class FixEndToEndTest < Minitest::Test
  include FixHelper

  ROOT = File.expand_path("../..", __dir__)
  SEED = "def %s\n  1\nrescue Exception => e\n  e\nend\n"
  CLAUDE = <<~RUBY
    #!#{RbConfig.ruby}
    require "json"
    prompt = $stdin.read
    path = prompt[/Repair these Law findings in (\\S+)\\./, 1]
    text = File.read(path).gsub("rescue Exception", "rescue StandardError")
    File.open(File.expand_path("../asked", __dir__), File::APPEND | File::CREAT | File::WRONLY) { |f| f.puts(path) }
    puts JSON.generate("type" => "result", "is_error" => false, "result" => "```ruby\\n\#{text}```",
                       "usage" => { "input_tokens" => 40, "output_tokens" => 20 }, "total_cost_usd" => 0.001)
  RUBY

  def stub(root, name, text)
    put(root, "stubs/bin/#{name}", text)
    File.chmod(0o755, File.join(root, "stubs/bin", name))
  end

  def fixture(root)
    %w[lib/keep.rb lib/refuse.rb registry/locked.rb].each { |path| put(root, "repo/#{path}", format(SEED, File.basename(path, ".rb"))) }
    repo = File.join(root, "repo")
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "fix@test")
    git(repo, "config", "user.name", "fix test")
    put(repo, ".gitignore", "tmp/\nlog/\n")
    commit_all(repo)
    put(repo, ".git/hooks/pre-commit", "#!/bin/sh\ngit diff --cached --name-only | grep -q refuse.rb && { echo 'hook: refuse.rb refused' >&2; exit 1; }\nexit 0\n")
    File.chmod(0o755, File.join(repo, ".git/hooks/pre-commit"))
    stub(root, "claude", CLAUDE)
    stub(root, "sysctl", "#!/bin/sh\necho '{ 0.50 0.50 0.50 }'\n")
    repo
  end

  def fix(root, repo)
    path = [File.join(root, "stubs/bin"), File.dirname(RbConfig.ruby), "/usr/bin", "/bin"].join(":")
    env = ["PATH=#{path}", "HOME=#{root}", "PUB5_MODEL=claude-cli:stub", "PUB5_LEDGER=#{File.join(root, 'ledger.jsonl')}"]
    world(root, { exec: ["env"] }, protected_paths: [])
      .exec("env", "-i", *env, RbConfig.ruby, File.join(ROOT, "bin/master"), "fix", repo, "--focus", "RESCUE_EXCEPTION", timeout: 300)
  end

  def test_bin_master_fix_repairs_puts_back_and_skips_end_to_end
    sandbox do |root|
      repo = fixture(root)
      run = fix(root, repo)

      assert run.ok?, "#{run.out}\n#{run.err}"
      assert_match(/landed 1, refused 2: commit_refused 1, skip_protected 1/, run.out)
      log = git(repo, "log", "--format=%s")
      assert_equal ["Repair RESCUE_EXCEPTION in keep.rb", "Seed the fixture"], log.lines.map(&:chomp)
      message = git(repo, "log", "-1", "--format=%B")
      assert_empty Fix::CommitMessage.problems(message)
      assert_match(/^Measured: 1 -> 0 findings in lib\/keep.rb$/, message)
      assert_includes File.read(File.join(repo, "lib/keep.rb")), "rescue StandardError"
      assert_includes File.read(File.join(repo, "lib/refuse.rb")), "rescue Exception", "the refused repair is put back"
      assert_empty git(repo, "status", "--porcelain")
      refusal = JSON.parse(File.read(File.join(repo, "log/fix_refusals.jsonl")).lines.last)
      assert_equal %w[lib/refuse.rb commit restored], refusal.values_at("file", "stage", "outcome")
      refute_includes File.read(File.join(root, "stubs/asked")), "registry/locked.rb", "the protected file never reached the model"
      llm = File.readlines(File.join(root, "ledger.jsonl")).map { |l| JSON.parse(l) }.select { |e| e["kind"] == "llm" }
      assert_equal [60] * llm.size, llm.map { |e| e["tokens_in"] + e["tokens_out"] }
      assert_operator llm.size, :>=, 2
    end
  end
end
