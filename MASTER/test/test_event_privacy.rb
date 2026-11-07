# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/trace/event_privacy"
require "json"

class TestEventPrivacy < Minitest::Test
  def test_unknown_nested_objects_and_arrays_are_digest_only
    nested = {
      authorization: "Bearer nested-secret",
      metadata: { query: "private search", session: "session-secret" },
    }
    labels = ["private label", "another secret"]
    persisted = Master::Trace::EventPrivacy.persisted(
      "route:chosen",
      status: "ok", metadata: nested, labels:, elapsed_ms: 120,
    )
    json = JSON.generate(persisted)

    assert_equal "ok", persisted.fetch(:status)
    assert_equal 120, persisted.fetch(:elapsed_ms)
    assert_equal 64, persisted.fetch(:metadata_digest).length
    assert_equal JSON.generate(nested).bytesize, persisted.fetch(:metadata_bytes)
    assert_equal 64, persisted.fetch(:labels_digest).length
    assert_equal JSON.generate(labels).bytesize, persisted.fetch(:labels_bytes)
    refute_includes json, "nested-secret"
    refute_includes json, "private search"
    refute_includes json, "session-secret"
    refute_includes json, "private label"
    refute_includes json, "another secret"
  end

  def test_unrecognized_scalar_objects_are_digest_only
    secret_object = Object.new
    secret_object.define_singleton_method(:to_json) { |*_args| '"object-secret"' }
    persisted = Master::Trace::EventPrivacy.persisted(
      "custom:event", extension: secret_object
    )
    json = JSON.generate(persisted)

    assert_equal 64, persisted.fetch(:extension_digest).length
    refute_includes json, "object-secret"
  end

  def test_personal_identifiers_are_digest_only_even_when_numeric
    persisted = Master::Trace::EventPrivacy.persisted(
      "identity:observed",
      user_id: 123_456_789,
      phone: 4_799_911_122,
      email: "person@example.invalid",
      session: "session-bearer",
    )
    json = JSON.generate(persisted)

    assert_equal 64, persisted.fetch(:user_id_digest).length
    assert_equal 64, persisted.fetch(:phone_digest).length
    assert_equal 64, persisted.fetch(:email_digest).length
    assert_equal 64, persisted.fetch(:session_digest).length
    refute_includes json, "123456789"
    refute_includes json, "4799911122"
    refute_includes json, "person@example.invalid"
    refute_includes json, "session-bearer"
  end

  def test_undeclared_scalar_strings_are_digest_only_but_model_metadata_is_kept
    persisted = Master::Trace::EventPrivacy.persisted(
      "route:chosen",
      label: "private user-provided label",
      custom_value: "token=private",
      model: "grok-cli:auto",
      provider: "anthropic",
    )
    json = JSON.generate(persisted)

    assert_equal "grok-cli:auto", persisted.fetch(:model)
    assert_equal "anthropic", persisted.fetch(:provider)
    assert_equal 64, persisted.fetch(:label_digest).length
    assert_equal 64, persisted.fetch(:custom_value_digest).length
    refute_includes json, "private user-provided label"
    refute_includes json, "token=private"
  end

  def test_malformed_reserved_metadata_is_digest_only
    persisted = Master::Trace::EventPrivacy.persisted(
      "route:chosen",
      status: "private status token=secret",
      elapsed_ms: "duration token=secret",
      success: "secret-not-a-boolean",
    )
    json = JSON.generate(persisted)

    assert_equal 64, persisted.fetch(:status_digest).length
    assert_equal 64, persisted.fetch(:elapsed_ms_digest).length
    assert_equal 64, persisted.fetch(:success_digest).length
    refute_includes json, "private status token=secret"
    refute_includes json, "duration token=secret"
    refute_includes json, "secret-not-a-boolean"
  end

  def test_effect_lifecycle_preserves_reversibility_and_replay_safety_metadata
    persisted = Master::Trace::EventPrivacy.persisted(
      "core:effect:before",
      reversibility: "reversible",
      replay_requires_reconciliation: false,
    )

    assert_equal "reversible", persisted.fetch(:reversibility)
    assert_equal false, persisted.fetch(:replay_requires_reconciliation)
    refute persisted.key?(:reversibility_digest)
    refute persisted.key?(:replay_requires_reconciliation_digest)
  end

  def test_exception_telemetry_publishers_use_digest_only_diagnostics
    publishers = {
      "lib/review/agent.rb" => %w[llm:record_error],
      "lib/review/agent/model_selector.rb" => %w[llm:pinned_model_unavailable llm:route_error],
      "lib/review/agent/model_override.rb" => %w[llm:model_state_error llm:model_reachability_error llm:model_switch_error],
      "lib/review/agent/fallback_chain.rb" => %w[llm:dynamic_route_error],
      "lib/review/llm_dispatcher.rb" => %w[llm:preflight_error],
      "lib/review/llm_dispatcher/tool_registry.rb" => %w[agent:llm_tools_error],
      "lib/review/llm_dispatcher/ruby_llm_sender.rb" => %w[cost:record_error cost:cache_write_pricing_error],
      "lib/trace/metrics.rb" => %w[metrics:record_error metrics:append_error],
    }

    publishers.each do |relative_path, events|
      source = File.read(File.join(Master::ROOT, relative_path))
      events.each do |event|
        publisher = source.lines.find { |line| line.include?("publish(\"#{event}\"") }
        refute_nil publisher, "#{relative_path} lost publisher for #{event}"
        assert_includes publisher, "Master::Execution::Contract.diagnostic_fields", event
        assert_includes publisher, "error_class:", event
        refute_match(/\berror:\s*(?:e|err)\.message/, publisher, "#{event} leaked raw exception text")
      end
    end
  end

  def test_common_identity_and_location_fields_are_digest_only
    private_fields = {
      username: "private-user",
      email: "person@example.invalid",
      address: "1 Private Road",
      display_name: "Private Person",
      details: "confidential details",
      value: "one-time-token-value",
    }
    persisted = Master::Trace::EventPrivacy.persisted("profile:updated", private_fields)
    json = JSON.generate(persisted)

    private_fields.each do |field, value|
      assert_equal 64, persisted.fetch("#{field}_digest".to_sym).length
      refute_includes json, value
    end
  end

  # A receipt names what it is a receipt for. Digesting `worker` and `job`
  # would leave a worker:before with no after unable to say which worker or
  # which job was cut short, which is the whole reason the receipt exists.
  # The exception is narrow: a job name is one line of prose, and every field
  # that can carry personal data stays digest-only.
  def test_a_receipt_names_its_worker_and_job_without_keeping_prose_payloads
    kept = Master::Trace::EventPrivacy.persisted(
      "worker:before", worker: "task_steward", job: "mission 7", pid: 4_242,
    )

    assert_equal "task_steward", kept.fetch(:worker)
    assert_equal "mission 7", kept.fetch(:job)
    assert_equal 4_242, kept.fetch(:pid)

    newline = Master::Trace::EventPrivacy.persisted("worker:before", job: "sweep\nprivate line")
    assert_equal 64, newline.fetch(:job_digest).length, "a name is one line, never a payload"
    refute_includes JSON.generate(newline), "private line"

    prose = Master::Trace::EventPrivacy.persisted(
      "worker:before", worker: "heartbeat", job: "canary",
      goal: "person@example.invalid wants their records", reason: "private reason",
    )
    refute_includes JSON.generate(prose), "person@example.invalid"
    assert_equal 64, prose.fetch(:goal_digest).length
    assert_equal 64, prose.fetch(:reason_digest).length
  end

  def test_sensitive_scalars_remain_digest_only
    persisted = Master::Trace::EventPrivacy.persisted(
      "route:chosen", query: "https://internal.invalid/?token=secret", outcome: "ok"
    )

    assert_equal "ok", persisted.fetch(:outcome)
    assert_equal 64, persisted.fetch(:query_digest).length
    refute_includes JSON.generate(persisted), "token=secret"
  end

  # The bus, the append, the read-back, the recorder and telemetry each apply
  # this transform, so one record passes through it repeatedly. A second pass
  # that digests the first pass's own output destroys size metadata: 16 bytes
  # of tool arguments came back as `arguments_bytes_bytes: 2`, which left
  # ToolObserver unable to rebuild its crash quarantine after a restart.
  def test_persisted_is_idempotent_so_repeated_layers_keep_size_metadata
    once = Master::Trace::EventPrivacy.persisted(
      "tool:execution:before",
      invocation_id: "inv-1", tool: "write_file", tier: "guarded",
      arguments_digest: "a" * 64, arguments_bytes: 4_096, pid: 42,
    )

    3.times { once = Master::Trace::EventPrivacy.persisted("tool:execution:before", once) }

    assert_equal 4_096, once.fetch(:arguments_bytes)
    assert_equal "a" * 64, once.fetch(:arguments_digest)
    assert_equal 42, once.fetch(:pid)
    refute once.key?(:arguments_bytes_bytes)
  end
end
