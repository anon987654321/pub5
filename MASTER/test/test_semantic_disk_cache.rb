# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/law_tree"
require "tmpdir"
require "fileutils"

# The semantic disk cache lets an unattended chunked run resume its verdicts
# instead of re-paying every model call after a process restart (2026-11-10:
# the in-process cache died with each chunk and OPENBSD re-paid ~3 minutes of
# model calls for the same file every chunk, so passes never converged).
class TestSemanticDiskCache < Minitest::Test
  def semantic_law_class = Master::Review::Scan::Laws::SemanticLaw

  def with_cache_file
    Dir.mktmpdir("semantic-cache") do |dir|
      path = File.join(dir, "semantic_cache.jsonl")
      ENV["MASTER_SEMANTIC_CACHE"] = "1"
      ENV["MASTER_SEMANTIC_CACHE_PATH"] = path
      yield path
    end
  ensure
    ENV["MASTER_SEMANTIC_CACHE"] = "0"
    ENV.delete("MASTER_SEMANTIC_CACHE_PATH")
  end

  def agent_that_counts(replies)
    calls = 0
    replies = replies.transform_keys(&:to_sym)
    agent = Object.new
    agent.define_singleton_method(:ask) do |_prompt, operation:|
      calls += 1
      replies.fetch(operation) { raise "unexpected operation #{operation}" }
    end
    [agent, -> { calls }]
  end

  def agent_that_refuses
    agent = Object.new
    agent.define_singleton_method(:ask) { |_prompt, operation:| raise "model must not be called (#{operation})" }
    agent
  end

  def with_source(code)
    Dir.mktmpdir("semantic-source") do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, code)
      yield path
    end
  end

  def one_law_id
    @one_law_id ||= semantic_law_class.new(agent: nil).send(:laws_for, nil).keys.first
  end

  def test_second_instance_serves_cached_verdicts_without_model_calls
    with_cache_file do
      with_source("value = 1\n") do |path|
        code = File.read(path)
        agent, calls = agent_that_counts(
          "scan_semantic_violations" => "#{one_law_id}:3:a cached breach",
          "scan_semantic_opportunities" => "NONE",
        )
        findings = semantic_law_class.new(agent:).check(code, path:)
        assert_equal 1, findings.size
        assert_equal 2, calls.call, "one call per stream on a cold cache"

        again = semantic_law_class.new(agent: agent_that_refuses).check(code, path:)
        assert_equal 1, again.size, "the cached verdict must survive the process restart"
        assert_equal one_law_id, again.first.law.to_s
        assert_equal 3, again.first.line
        assert_equal 0, calls.call - 2, "a warm disk cache must not call the model"
      end
    end
  end

  def test_changed_code_misses_the_cache
    with_cache_file do
      with_source("value = 1\n") do |path|
        agent, calls = agent_that_counts(
          "scan_semantic_violations" => "CLEAN",
          "scan_semantic_opportunities" => "NONE",
        )
        semantic_law_class.new(agent:).check(File.read(path), path:)
        assert_equal 2, calls.call

        File.write(path, "value = 2\n")
        semantic_law_class.new(agent:).check(File.read(path), path:)
        assert_equal 4, calls.call, "a changed source must be judged again, not read from cache"
      end
    end
  end

  def test_a_clean_verdict_is_cached_as_an_empty_result_not_a_miss
    with_cache_file do
      with_source("value = 1\n") do |path|
        code = File.read(path)
        agent, calls = agent_that_counts(
          "scan_semantic_violations" => "CLEAN",
          "scan_semantic_opportunities" => "NONE",
        )
        assert_equal [], semantic_law_class.new(agent:).check(code, path:)
        assert_equal 2, calls.call

        assert_equal [], semantic_law_class.new(agent: agent_that_refuses).check(code, path:)
        assert_equal 2, calls.call, "CLEAN must be cached, not re-asked"
      end
    end
  end

  def test_disabled_cache_never_touches_the_disk
    Dir.mktmpdir("semantic-cache-off") do |dir|
      path = File.join(dir, "semantic_cache.jsonl")
      ENV["MASTER_SEMANTIC_CACHE"] = "0"
      ENV["MASTER_SEMANTIC_CACHE_PATH"] = path
      with_source("value = 1\n") do |source|
        agent, = agent_that_counts(
          "scan_semantic_violations" => "CLEAN",
          "scan_semantic_opportunities" => "NONE",
        )
        assert_equal [], semantic_law_class.new(agent:).check(File.read(source), path:)
        refute File.exist?(path), "a disabled cache must not write"
      end
    end
  ensure
    ENV["MASTER_SEMANTIC_CACHE"] = "0"
    ENV.delete("MASTER_SEMANTIC_CACHE_PATH")
  end
end
