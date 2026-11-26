# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/io/catalog_index"

class ProviderCatalogIndexSpec < Minitest::Test
  def with_index
    Dir.mktmpdir do |dir|
      yield Master::Io::CatalogIndex.new(db_path: File.join(dir, "catalog.sqlite3")), dir
    end
  end

  def test_imports_openrouter_models
    with_index do |index, dir|
      path = File.join(dir, "openrouter.json")
      File.write(path, JSON.generate({
        "data" => [{
          "id" => "openai/gpt-test",
          "name" => "GPT Test",
          "context_length" => 128_000,
          "pricing" => { "prompt" => "0.1", "completion" => "0.2" },
          "architecture" => { "input_modalities" => ["text"], "output_modalities" => ["text"], "tokenizer" => "test" },
        }],
      }))

      assert_equal 1, index.import_file("openrouter", path, normalizer: "openrouter")
      row = index.search("gpt-test").first
      assert_equal "openai/gpt-test", row["id"]
      assert_equal 128_000, row["context_length"]
    end
  end

  def test_imports_replicate_results_payload
    with_index do |index, dir|
      path = File.join(dir, "replicate.json")
      File.write(path, JSON.generate({
        "results" => [{
          "owner" => "black-forest-labs",
          "name" => "flux-schnell",
          "description" => "fast image model",
          "tags" => %w[image fast],
        }],
      }))

      assert_equal 1, index.import_file("replicate", path, normalizer: "replicate")
      row = index.search("flux", source: "replicate").first
      assert_equal "black-forest-labs/flux-schnell", row["id"]
      assert_match(/image/, row["tags"])
    end
  end

  def test_malformed_json_raises_cleanly
    with_index do |index, dir|
      path = File.join(dir, "bad.json")
      File.write(path, "{")
      assert_raises(JSON::ParserError) { index.import_file("replicate", path, normalizer: "replicate") }
    end
  end

  # The free-lane ranking wants a measured answer time that outlives the
  # process. The catalog carries it as free_latency_s on the model row, and a
  # provider snapshot refresh must not erase the measurement.
  def test_records_and_answers_a_free_latency_measurement
    with_index do |index, dir|
      import_openrouter_row(index, dir, "nvidia/nemotron-3-ultra-550b-a55b:free")
      assert_nil index.free_latency_s("nvidia/nemotron-3-ultra-550b-a55b:free")

      index.record_free_latency(source: "openrouter", id: "nvidia/nemotron-3-ultra-550b-a55b:free", seconds: 12.5)

      assert_in_delta 12.5, index.free_latency_s("nvidia/nemotron-3-ultra-550b-a55b:free")
      assert_in_delta 12.5, index.search("nemotron").first["free_latency_s"]
      assert_raises(ArgumentError) do
        index.record_free_latency(source: "openrouter", id: "x:free", seconds: -1)
      end
    end
  end

  def test_a_snapshot_refresh_carries_the_measured_latency_across
    with_index do |index, dir|
      import_openrouter_row(index, dir, "nvidia/nemotron-3-ultra-550b-a55b:free")
      index.record_free_latency(source: "openrouter", id: "nvidia/nemotron-3-ultra-550b-a55b:free", seconds: 9.0)

      import_openrouter_row(index, dir, "nvidia/nemotron-3-ultra-550b-a55b:free")

      actual = index.free_latency_s("nvidia/nemotron-3-ultra-550b-a55b:free")
      # The refresh replaces the row; this checkout's measurement survives it.
      assert_in_delta 9.0, actual
    end
  end

  def test_provider_catalog_fetch_uses_the_shared_pinned_bounded_request
    with_index do |index, _dir|
      uri = URI("https://catalog.example.test/models")
      payload = { "data" => [{ "id" => "provider/model" }] }
      response = Net::HTTPOK.new("1.1", "200", "OK")
      # The guard has already consumed the streamed body before returning. A
      # raw Net::HTTPResponse has no active stream in this unit test, so expose
      # the consumed payload directly instead of invoking its socket-backed
      # body reader outside Net::HTTP#request.
      response.define_singleton_method(:body) { JSON.generate(payload) }
      calls = []
      handler = lambda do |candidate, request, **options|
        calls << [candidate, request, options]
        response
      end

      Master::Io::SsrfGuard.stub(:request, handler) do
        assert_equal payload, index.send(:fetch_json, uri.to_s, token: "catalog-token")
      end

      candidate, request, options = calls.fetch(0)
      assert_equal uri, candidate
      assert_instance_of Net::HTTP::Get, request
      assert_equal "Bearer catalog-token", request["Authorization"]
      assert_equal "application/json", request["Accept"]
      assert_equal 8 * 1024 * 1024, options.fetch(:max_bytes)
      assert_equal 30, options.fetch(:timeout)
      assert_equal 10, options.fetch(:open_timeout)
      assert_equal 30, options.fetch(:read_timeout)
      assert_equal 10, options.fetch(:write_timeout)
    end
  end

  def import_openrouter_row(index, dir, id)
    path = File.join(dir, "openrouter.json")
    File.write(path, JSON.generate({ "data" => [{ "id" => id, "name" => id }] }))
    index.import_file("openrouter", path, normalizer: "openrouter")
  end
end
