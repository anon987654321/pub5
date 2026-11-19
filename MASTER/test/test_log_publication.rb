# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/log_publication"

# LogPublication posts the /fix run's log to a gist or keyless pastebin after
# each run. Every test here drives an injected HTTP double; nothing leaves the
# machine. The contract under test: redaction with a residue refusal, the
# 512KB tail bound, the env gates, and fail-soft behavior on network errors.
class LogPublicationTest < Minitest::Test
  Publication = Master::Fix::LogPublication

  def publish(log_text:, env: {}, http: nil)
    Publication.new(http: http || ->(*) { flunk("unexpected network call") })
               .publish(run_id: "run-1", log_text:, env:)
  end

  def test_gist_sink_with_token
    calls = []
    http = lambda do |url, payload, headers, **_opts|
      calls << [url, payload, headers]
      { "html_url" => "https://gist.github.com/anon/deadbeef", "__status" => 201 }
    end
    result = publish(log_text: "hello run", env: { "GITHUB_TOKEN" => "tok" }, http:)

    assert_equal "gist", result.sink
    assert_equal "https://gist.github.com/anon/deadbeef", result.url
    assert_equal true, result.redacted
    refute result.truncated
    url, payload, headers = calls.first
    assert_equal Publication::GIST_API, url
    assert_equal "Bearer tok", headers["Authorization"]
    assert_equal false, payload[:public]
    assert_equal "hello run", payload[:files]["fix-run-1.log"][:content]
  end

  def test_gh_token_fallback
    http = ->(*) { { "html_url" => "https://gist.github.com/anon/x" } }
    result = publish(log_text: "body", env: { "GH_TOKEN" => "tok2" }, http:)
    assert_equal "gist", result.sink
  end

  def test_ix_sink_without_token
    calls = []
    http = lambda do |url, _payload, _headers, form: false|
      calls << [url, form]
      "https://ix.io/abc123\n"
    end
    result = publish(log_text: "plain log", env: {}, http:)

    assert_equal "ix.io", result.sink
    assert_equal "https://ix.io/abc123", result.url
    assert_equal [[Publication::IX_IO, true]], calls
  end

  def test_secrets_are_redacted_before_upload
    captured = nil
    http = lambda do |_url, payload, _headers, **_opts|
      captured = payload[:files]["fix-run-1.log"][:content]
      { "html_url" => "https://gist.github.com/anon/red" }
    end
    result = publish(log_text: "boot\nOPENAI_API_KEY=sk-livevalue123\ndone\n",
                     env: { "GITHUB_TOKEN" => "tok" }, http:)

    assert_equal "gist", result.sink
    assert_includes captured, "OPENAI_API_KEY=__REDACTED__"
    refute_includes captured, "sk-livevalue123"
  end

  def test_residue_audit_refuses_unredactable_secret
    # A secret-shaped line no value-pattern pins (bare `smtp_url=` style) must
    # never leave the box: the residue audit refuses the whole upload.
    result = publish(log_text: "postmaster_password: hunter2\n", env: {})

    assert_nil result.sink
    assert_nil result.url
    assert_match(/residue audit refused/, result.skipped)
  end

  def test_opt_out
    result = publish(log_text: "x", env: { "PUB5_FIX_LOG_PUBLISH" => "0" })
    assert_match(/disables publication/, result.skipped)
    result = publish(log_text: "x", env: { "PUB5_FIX_LOG_PUBLISH" => "off" })
    assert_match(/disables publication/, result.skipped)
  end

  def test_proof_suite_gate
    # Under MASTER_IN_PROOF the default is off; an explicit =1 forces it on.
    result = publish(log_text: "x", env: { "MASTER_IN_PROOF" => "1" })
    assert_match(/MASTER_IN_PROOF/, result.skipped)

    http = ->(*) { "https://ix.io/forced" }
    result = publish(log_text: "x", env: { "MASTER_IN_PROOF" => "1", "PUB5_FIX_LOG_PUBLISH" => "1" }, http:)
    assert_equal "ix.io", result.sink
  end

  def test_network_error_is_fail_soft
    http = ->(*) { raise Errno::ECONNREFUSED, "connection refused" }
    result = publish(log_text: "x", env: {}, http:)

    assert_nil result.sink
    assert_match(/ECONNREFUSED/, result.error)
  end

  def test_gist_without_url_is_fail_soft
    http = ->(*) { { "message" => "Bad credentials", "__status" => 401 } }
    result = publish(log_text: "x", env: { "GITHUB_TOKEN" => "bad" }, http:)

    assert_nil result.sink
    assert_match(/no url/, result.error)
  end

  def test_tail_bounded_at_max_bytes
    captured = nil
    http = lambda do |_url, payload, _headers, **_opts|
      captured = payload[:files]["fix-run-1.log"][:content]
      { "html_url" => "https://gist.github.com/anon/big" }
    end
    big = "a" * (Publication::MAX_BYTES + 100_000)
    result = publish(log_text: big, env: { "GITHUB_TOKEN" => "tok" }, http:)

    assert_equal true, result.truncated
    assert captured.bytesize <= Publication::MAX_BYTES + 100
    assert captured.start_with?("[log truncated")
  end

  def test_command_line_helper_uses_the_redacting_publisher
    source = File.read(File.expand_path("../../scripts/publish_log.zsh", __dir__))

    assert_includes source, "Master::Fix::LogPublication.publish"
    refute_includes source, "curl -F"
  end

  def test_result_to_h_compacts
    skipped = Publication::Result.new(skipped: "why").to_h
    assert_equal({ skipped: "why" }, skipped)
    ok = Publication::Result.new(sink: "gist", url: "u", redacted: true, truncated: false).to_h
    assert_equal "gist", ok[:sink]
    assert_equal "u", ok[:url]
  end
end
