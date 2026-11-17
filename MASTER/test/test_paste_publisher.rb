# frozen_string_literal: true

require_relative "test_helper"
require "json"

class PastePublisherTest < Minitest::Test
  Response = Struct.new(:code, :body, :headers) do
    def [](name)
      headers.to_h[name.to_s.downcase]
    end
  end

  def response(code, body, headers = {})
    Response.new(code.to_s, body, headers.transform_keys(&:downcase))
  end

  def test_build_report_redacts_credentials_private_keys_and_local_paths
    publisher = Master::Ground::PastePublisher.new(root: "/home/operator/pub5")
    token = "ghp_#{'A' * 36}"
    private_key = <<~KEY
      -----BEGIN PRIVATE KEY-----
      private-key-material
      -----END PRIVATE KEY-----
    KEY
    raw = [
      "PASSWORD=hunter2",
      "contact ops@example.com",
      "RAILS_MASTER_KEY=master-secret",
      "DATABASE_URL=postgres://svc:db-secret@example.test/app",
      "Authorization: Bearer #{'B' * 32}",
      "https://deploy:secret@example.test/hook?token=one-time",
      token,
      private_key,
      "/home/operator/pub5/MASTER/bin/check",
    ].join("\n")

    report = publisher.build_report(operation: "/check", status: "success", output: raw)

    assert_includes report, "status: success"
    assert_includes report, "operation: /check"
    assert_includes report, "[PRIVATE KEY BLOCK REDACTED]"
    assert_includes report, "$REPO/MASTER/bin/check"
    %w[hunter2 master-secret db-secret secret one-time private-key-material].each { |secret| refute_includes report, secret }
    refute_includes report, "ops@example.com"
    assert_includes report, "[EMAIL REDACTED]"
    refute_includes report, token
    refute_includes report, "deploy:secret@"
  end

  def test_report_is_bounded_before_upload
    publisher = Master::Ground::PastePublisher.new
    report = publisher.build_report(operation: "/fix", status: "success", output: "x" * 150_000)

    assert_operator report.bytesize, :<=, Master::Ground::PastePublisher::MAX_BYTES + 80
    assert_includes report, "[operation log truncated"
  end

  def test_pste_us_success_returns_a_validated_one_day_link
    calls = []
    transport = lambda do |uri:, body:, headers:|
      calls << [uri, body, headers]
      response(201, JSON.generate("ok" => true, "data" => { "url" => "https://pste.us/abc123" }))
    end
    publisher = Master::Ground::PastePublisher.new(transport:)

    outcome = publisher.publish(operation: "/check", status: "success", output: "checks passed")

    assert outcome.success?
    assert_equal :pste_us, outcome.service
    assert_equal "https://pste.us/abc123", outcome.url
    assert_equal "1 day", outcome.expires_in
    payload = JSON.parse(calls.fetch(0)[1])
    assert_equal "1d", payload.fetch("expires_in")
    assert_includes payload.fetch("content"), "checks passed"
  end

  def test_dpaste_is_used_when_pste_is_unavailable_and_expires_after_seven_days
    calls = []
    transport = lambda do |uri:, body:, headers:|
      calls << [uri, body, headers]
      if uri.host == "pste.us"
        response(503, "temporarily unavailable")
      else
        response(200, "https://dpaste.org/xyz789")
      end
    end
    publisher = Master::Ground::PastePublisher.new(transport:)

    outcome = publisher.publish(operation: "/fix RAILS", status: "failure", output: "one test failed")

    assert outcome.success?
    assert_equal :dpaste_org, outcome.service
    assert_equal "https://dpaste.org/xyz789", outcome.url
    assert_equal "7 days", outcome.expires_in
    assert_equal 2, calls.size
    assert_includes calls.fetch(1)[1], "expires=604800"
    assert_includes calls.fetch(1)[1], "format=url"
  end

  def test_untrusted_response_urls_are_never_announced
    transport = lambda do |uri:, body:, headers:|
      if uri.host == "pste.us"
        response(200, JSON.generate("ok" => true, "data" => { "url" => "https://attacker.example/paste" }))
      else
        response(200, "https://attacker.example/paste")
      end
    end
    publisher = Master::Ground::PastePublisher.new(transport:)

    outcome = publisher.publish(operation: "/check", status: "success", output: "done")

    refute outcome.success?
    assert_nil outcome.url
  end

  def test_disabled_publishing_does_not_contact_a_provider
    called = false
    transport = ->(**) { called = true }
    publisher = Master::Ground::PastePublisher.new(transport:, enabled: "0")

    outcome = publisher.publish(operation: "/check", status: "success", output: "done")

    refute outcome.success?
    assert_equal :disabled, outcome.error
    refute called
  end

  def test_content_bearing_commands_are_not_publicly_published
    %w[/documents /memory /read /write /ask /chat /email /message /forget /pair].each do |command|
      refute Master::Ground::PastePublisher.operation_request?(command), command
    end
    assert Master::Ground::PastePublisher.operation_request?("/fix RAILS")
    assert Master::Ground::PastePublisher.operation_request?("please run the tests")
    assert Master::Ground::PastePublisher.operation_request?("also assess the Qwen proposal")
    assert Master::Ground::PastePublisher.operation_request?("go on")
    assert Master::Ground::PastePublisher.operation_request?("!zsh OPENBSD/bin/rehearse")
    refute Master::Ground::PastePublisher.operation_request?("!cat secrets.env")
  end
end
