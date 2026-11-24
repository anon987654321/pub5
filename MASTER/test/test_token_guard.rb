# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/token_guard"
require "open3"
require "tmpdir"

# A PAT pasted into chat on 2026-11-23 had nothing between it and a commit. The
# fake credentials below are assembled at run time so this file never carries a
# token-shaped literal of its own.
class TestTokenGuard < Minitest::Test
  TOKEN = ("ghp_" + ("Qx7Lm2Vz" * 5)).freeze
  GUARD = File.expand_path("../tools/token_guard.rb", __dir__)

  def diff_adding(line, path: "scripts/deploy.sh", start: 10)
    "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n@@ -1,0 +#{start},1 @@\n+#{line}\n"
  end

  def test_an_added_token_is_found_with_its_file_and_line
    found = TokenGuard.scan(diff_adding("export GH=#{TOKEN}"))
    assert_equal [["scripts/deploy.sh", 10, "GitHub token"]], found.map { |f| [f.path, f.line, f.kind] }
  end

  def test_the_report_never_repeats_the_secret
    found = TokenGuard.scan(diff_adding("export GH=#{TOKEN}"))
    refute_includes TokenGuard.report(found), TOKEN
  end

  def test_removed_and_context_lines_are_not_read
    diff = "+++ b/a.rb\n@@ -1,2 +1,1 @@\n-token #{TOKEN}\n #{TOKEN}\n"
    assert_empty TokenGuard.scan(diff)
  end

  def test_obvious_placeholders_pass_like_the_scanner_fixtures
    ["ghp_abcdefghijklmnopqrstuvwxyz123456", "ghp_#{'a' * 36}", "ghp_EXAMPLE#{'Z9' * 10}"].each do |fake|
      assert_empty TokenGuard.scan(diff_adding(fake)), fake
    end
  end

  def test_other_credential_shapes_are_found
    assert_equal ["private key block"], TokenGuard.scan(diff_adding("-----BEGIN RSA " + "PRIVATE KEY-----")).map(&:kind)
    assert_equal ["Anthropic key"], TokenGuard.scan(diff_adding("k=sk-ant-#{'Rt4Yp8Ks' * 5}")).map(&:kind)
  end

  def test_the_cli_refuses_a_staged_token_and_the_override_allows_it
    Dir.mktmpdir do |dir|
      run = ->(*cmd, env: {}) { Open3.capture3(env, *cmd, chdir: dir) }
      run.call("git", "init", "-q")
      File.write(File.join(dir, "env.sh"), "GH=#{TOKEN}\n")
      run.call("git", "add", "env.sh")
      _o, err, status = run.call(RbConfig.ruby, GUARD)
      refute status.success?
      assert_match(/env\.sh:1/, err)
      refute_includes err, TOKEN
      _o, _e, status = run.call(RbConfig.ruby, GUARD, env: { "PUB5_ALLOW_TOKEN_SHAPE" => "1" })
      assert status.success?
    end
  end
end
