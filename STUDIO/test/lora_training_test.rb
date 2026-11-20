# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require_relative "../lora/train"

class TestStudioLoraTrainingRunner < Minitest::Test
  def test_preflight_failure_stops_before_any_provider_call
    validator = Object.new
    validator.define_singleton_method(:validate_subject) do |_subject|
      { "training_ready" => false, "blockers" => [{ "detail" => "private training consent is missing" }] }
    end
    client = Object.new
    %i[ensure_private_model! upload_zip train_lora].each do |method|
      client.define_singleton_method(method) do |*|
        flunk "provider must not be called before complete preflight"
      end
    end

    runner = Studio::Lora::Training::Runner.new(client:, validator:, root: Dir.pwd)
    error = assert_raises(Studio::Lora::Training::Error) do
      runner.run(subjects: ["johann"])
    end

    assert_match(/consent is missing/, error.message)
  end

  def test_unknown_and_duplicate_subjects_are_refused
    runner = Studio::Lora::Training::Runner.new(client: Object.new, validator: Object.new, root: Dir.pwd)

    assert_raises(ArgumentError) { runner.send(:normalize_subjects, ["johann", "johann"]) }
    assert_raises(ArgumentError) { runner.send(:normalize_subjects, ["unknown"]) }
  end

  def test_all_three_subjects_are_the_default_batch
    assert_equal %w[johann ragnhild merethe], Studio::Lora::Training::SUBJECTS
  end
end
