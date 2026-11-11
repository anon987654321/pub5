# frozen_string_literal: true

require_relative "test_helper"
require "master"
require "timeout"

class TestMemory < Minitest::Test
  def setup
    @root = Dir.mktmpdir("master_memory_test")
    @mem  = Master::Ground::Memory.new(root: @root)
  end

  def without_brain_keys(mem = @mem)
    %w[brain/memory brain/tools brain/identity].each { |key| mem.forget(key) }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_slow_embedding_does_not_hold_the_cross_process_memory_lock
    embedding_started = Queue.new
    release_embedding = Queue.new
    fast_write_finished = Queue.new
    original = Master::Review::Embeddings.method(:embed)
    original_enabled = Master::Review::Embeddings.method(:enabled?)
    Master::Review::Embeddings.define_singleton_method(:enabled?) { true }
    Master::Review::Embeddings.define_singleton_method(:embed) do |text, *arguments, **keywords|
      if text == "slow_key slow value"
        embedding_started << true
        release_embedding.pop
        nil
      else
        original.call(text, *arguments, **keywords)
      end
    end

    slow = Thread.new { Master::Ground::Memory.new(root: @root).remember("slow_key", "slow value") }
    embedding_started.pop
    fast = Thread.new do
      Master::Ground::Memory.new(root: @root).remember("fast_key", "fast value", embed: false)
      fast_write_finished << true
    end

    assert_equal true, Timeout.timeout(2) { fast_write_finished.pop }
    release_embedding << true
    [slow, fast].each(&:join)
    assert_equal "slow value", @mem.recall("slow_key")
    assert_equal "fast value", @mem.recall("fast_key")
  ensure
    release_embedding << true if release_embedding
    [slow, fast].compact.each(&:join)
    Master::Review::Embeddings.define_singleton_method(:embed, original) if original
    Master::Review::Embeddings.define_singleton_method(:enabled?, original_enabled) if original_enabled
  end

  def test_consolidation_sees_entries_written_by_another_memory_instance
    stale = Master::Ground::Memory.new(root: @root)
    @mem.remember("arrived_later", "new durable fact", embed: false)

    result = stale.consolidate!

    assert_match(/1 entries checked/, result)
  end

  def test_stale_memory_instances_merge_each_others_writes
    first = Master::Ground::Memory.new(root: @root)
    second = Master::Ground::Memory.new(root: @root)

    first.remember("first_process", "first value", embed: false)
    second.remember("second_process", "second value", embed: false)

    assert_equal "first value", first.recall("first_process")
    assert_equal "second value", first.recall("second_process")
    assert_equal "first value", second.recall("first_process")
    assert_equal "second value", second.recall("second_process")
  end

  def test_memory_writes_from_two_processes_are_merged
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    ready_read, ready_write = IO.pipe
    start_read, start_write = IO.pipe
    children = %w[WORKER_ALPHA WORKER_BETA].map do |worker|
      fork do
        ready_read.close
        start_write.close
        ready_write.write("r")
        ready_write.flush
        start_read.read(1)
        Master::Ground::Memory.new(root: @root).remember("worker/#{worker}", worker, embed: false)
        exit! 0
      rescue StandardError
        exit! 1
      end
    end
    ready_write.close
    start_read.close
    2.times { ready_read.read(1) }
    start_write.write("xx")
    start_write.close
    statuses = children.map { |pid| Process.wait2(pid).last.exitstatus }
    assert_equal [0, 0], statuses

    assert_equal "WORKER_ALPHA", @mem.recall("worker/WORKER_ALPHA")
    assert_equal "WORKER_BETA", @mem.recall("worker/WORKER_BETA")
  ensure
    ready_read&.close unless ready_read&.closed?
    ready_write&.close unless ready_write&.closed?
    start_read&.close unless start_read&.closed?
    start_write&.close unless start_write&.closed?
    children&.each do |pid|
      Process.wait(pid) rescue Errno::ECHILD
    end
  end

  def test_memory_store_refuses_symlinked_parent_directories
    Dir.mktmpdir("memory-parent") do |root|
      outside = File.join(root, "outside")
      Dir.mkdir(outside)
      File.write(File.join(outside, "memory.yml"), { "outside" => { "value" => "private" } }.to_yaml)
      File.symlink(outside, File.join(root, ".master"))

      error = assert_raises(IOError) { Master::Ground::Memory.new(root:) }

      assert_match(/symlinked atomic-write directory component/, error.message)
      assert_equal "private", Master.load_yaml(File.join(outside, "memory.yml")).dig("outside", "value")
    end
  end

  def test_memory_version_does_not_follow_a_replaced_parent_symlink
    memory = @mem
    outside = File.join(@root, "outside")
    Dir.mkdir(outside)
    outside_file = File.join(outside, "memory.yml")
    File.write(outside_file, { "outside" => { "value" => "private" } }.to_yaml)
    File.symlink(outside, File.join(@root, ".master"))

    assert_equal "unknown", memory.version
    assert_equal "private", Master.load_yaml(outside_file).dig("outside", "value")
  end

  def test_corrupt_memory_store_is_preserved_and_not_replaced_with_an_empty_store
    Dir.mktmpdir("corrupt-memory") do |root|
      directory = File.join(root, ".master")
      FileUtils.mkdir_p(directory)
      path = File.join(directory, "memory.yml")
      corrupt = "memory: [unterminated\n"
      File.write(path, corrupt)

      error = assert_raises(IOError) { Master::Ground::Memory.new(root:) }

      assert_match(/memory store is malformed/, error.message)
      assert_equal corrupt, File.read(path)
    end
  end

  def test_remember_and_recall
    @mem.remember("test_key", "hello world", type: "general")
    assert_equal "hello world", @mem.recall("test_key")
  end

  def test_forget_removes_entry
    @mem.remember("bye", "gone soon")
    @mem.forget("bye")
    assert_nil @mem.recall("bye")
  end

  def test_forget_removes_archived_copy_and_conflict_history
    @mem.remember("deadline", "Friday", source: "conversation:1", confidence: 0.8)
    @mem.remember("deadline", "Monday", source: "conversation:2", confidence: 0.7)
    store = @mem.instance_variable_get(:@store)
    store["archive/deadline"] = { "value" => "Friday", "ts" => Time.now.to_i, "type" => "user" }
    store["archive/conflict/deadline/older"] = { "previous" => "Friday", "incoming" => "Monday", "ts" => Time.now.to_i }
    store["_consolidated_summary"] = { "value" => "The deadline used to be Friday.", "ts" => Time.now.to_i, "type" => "general" }

    assert_equal 1, @mem.conflicts_for("deadline").size
    @mem.forget("deadline")

    assert_nil @mem.recall("deadline")
    assert_nil @mem.recall("archive/deadline")
    refute @mem.instance_variable_get(:@store).key?("archive/conflict/deadline/older")
    assert_nil @mem.recall("_consolidated_summary")
    assert_empty @mem.conflicts_for("deadline")
    assert_equal 0, @mem.type_counts["user"]
  end

  def test_type_filtering
    @mem.remember("user_fact", "engineer", type: "user")
    @mem.remember("proj_fact", "deadline friday", type: "project")
    user = @mem.by_type("user")
    assert user.key?("user_fact")
    refute user.key?("proj_fact")
  end

  def test_type_counts
    without_brain_keys
    @mem.remember("a", "one", type: "user")
    @mem.remember("b", "two", type: "user")
    @mem.remember("c", "three", type: "feedback")
    counts = @mem.type_counts
    assert_equal 2, counts["user"]
    assert_equal 1, counts["feedback"]
  end

  def test_version_changes_only_when_persisted_memory_changes
    empty = @mem.version
    @mem.remember("version_test", "one")
    first = @mem.version
    @mem.remember("version_test", "two")
    second = @mem.version

    assert_equal "empty", empty
    assert_match(/\A[0-9a-f]{16}\z/, first)
    assert_match(/\A[0-9a-f]{16}\z/, second)
    refute_equal first, second
  end

  def test_reasoning_memory_round_trips_without_embedding
    frame = Master::Cognition::Intelligence.decision_frame(
      observation: "pass found two findings",
      hypothesis: "the highest-leverage one should be handled first",
      falsifier: "the next pass regresses",
      measurement: "next-pass finding count",
      source: "fix_loop:pass:1",
      selected: "ROOT",
      cause: "scan",
      effect: "repair candidate",
    )

    key = @mem.remember_reasoning(frame, key: "reasoning/test")
    assert_equal "reasoning/test", key
    rows = @mem.reasoning(limit: 1)
    assert_equal "fix_loop:pass:1", rows.first.fetch("source")
    assert_equal "ROOT", rows.first.fetch("selected")

    stored = @mem.by_type("reasoning").fetch("reasoning/test")
    refute stored.key?("vec"), "reasoning frames should not require embedding infrastructure"
  end

  def test_preference_memory_round_trips_without_embedding
    frame = Master::Cognition::Intelligence.preference_frame(
      domain: "music",
      preference: "leave more negative space between motifs",
      avoid: "dense continuous lead lines",
      evidence: "operator accepted sparse takes",
      source: "operator:feedback",
    )

    key = @mem.remember_preference(frame, key: "preference/music")
    assert_equal "preference/music", key
    row = @mem.preferences(limit: 1).first
    assert_equal "music", row.fetch("domain")
    assert_match(/negative space/, row.fetch("preference"))
    refute @mem.by_type("feedback").fetch(key).key?("vec")
  end

  def test_persistence_survives_reload
    @mem.remember("persist_key", "i survived", type: "reference")
    mem2 = Master::Ground::Memory.new(root: @root)
    assert_equal "i survived", mem2.recall("persist_key")
  end

  def test_new_memory_has_provenance_with_explicit_source_and_confidence
    @mem.remember("provenance", "captured", type: "user", source: "conversation:42", confidence: 0.9)

    provenance = @mem.provenance("provenance")

    assert_equal "conversation:42", provenance.fetch("source")
    assert_equal 0.9, provenance.fetch("confidence")
    assert_operator provenance.fetch("captured_at"), :>, 0
  end

  def test_legacy_memory_is_marked_low_confidence_when_reloaded
    path = File.join(@root, ".master", "memory.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, { "old" => { "value" => "old fact", "ts" => Time.now.to_i, "type" => "user" } }.to_yaml)

    mem = Master::Ground::Memory.new(root: @root)

    assert_equal "legacy", mem.provenance("old").fetch("source")
    assert_equal 0.0, mem.provenance("old").fetch("confidence")
  end

  def test_conflicting_memory_is_preserved_with_both_provenances
    @mem.remember("deadline", "Friday", source: "conversation:1", confidence: 0.8)
    @mem.remember("deadline", "Monday", source: "conversation:2", confidence: 0.7)

    conflicts = @mem.conflicts_for("deadline")

    assert_equal "Monday", @mem.recall("deadline")
    assert_equal 1, conflicts.size
    assert_equal "Friday", conflicts.first.fetch("previous")
    assert_equal "Monday", conflicts.first.fetch("incoming")
    assert_equal "conversation:1", conflicts.first.fetch("previous_provenance").fetch("source")
    assert_equal "conversation:2", conflicts.first.fetch("incoming_provenance").fetch("source")
  end

  # Identity is loaded from Master::Soul at runtime, not duplicated in memory.
  def test_markdown_identity_documents_are_not_a_memory_source
    fresh = Dir.mktmpdir("master-mem-brain-")
    FileUtils.mkdir_p(File.join(fresh, "data"))
    File.write(File.join(fresh, "data", "IDENTITY.md"), "# IDENTITY\n\nStale identity.\n")
    File.write(File.join(fresh, "data", "SOUL.md"), "# SOUL\n\nStale soul.\n")

    memory = Master::Ground::Memory.new(root: fresh)

    assert_nil memory.recall("brain/identity")
    assert_nil memory.recall("brain/soul")
  ensure
    FileUtils.rm_rf(fresh)
  end

  def test_auto_save_user_pattern
    key = @mem.auto_save("I'm a senior Ruby engineer at a startup")
    refute_nil key
    assert key.start_with?("auto/user/")
    value = @mem.recall(key)
    refute_nil value
    assert value.length >= 3
  end

  def test_auto_save_feedback_is_idempotent
    first = @mem.auto_save("prefer sparse layout with one strong action")
    second = @mem.auto_save("prefer sparse layout with one strong action")

    assert_equal first, second
    assert_equal 1, @mem.preferences(limit: 10).size
  end

  # A web visitor's sentence is not the operator's memory.
  def test_a_visitor_sentence_is_never_auto_saved
    Fiber[:master_visitor] = true
    assert_nil @mem.auto_save("I'm a nurse in Bergen")
  ensure
    Fiber[:master_visitor] = nil
  end

  def test_the_memory_file_is_owner_only
    @mem.auto_save("I'm a senior Ruby engineer at a startup")

    assert_equal 0o600, File.stat(File.join(@root, ".master", "memory.yml")).mode & 0o777
  end

  def test_auto_save_feedback_pattern
    key = @mem.auto_save("never use awk in zsh scripts, use parameter expansion instead")
    refute_nil key
    assert key.start_with?("auto/feedback/")
  end

  # Twelve user-typed fillers take all ten of context_summary's slots, since it
  # orders user entries first. That is the case recall exists for: a store too
  # big to inject whole.
  def fill_past_the_summary
    12.times { |i| @mem.remember("filler_#{i}", "unrelated note number #{i} about lunch", type: "user") }
  end

  def test_turn_recall_brings_back_an_entry_the_message_is_about
    @mem.remember("relayd_limit", "relayd discards response headers larger than eight kilobytes")
    fill_past_the_summary

    recalled = @mem.turn_recall("why does relayd drop the response headers?")

    assert_match(/relayd_limit/, recalled)
    assert_match(/not instructions/, recalled)
  end

  def test_turn_recall_needs_two_shared_words_and_stays_in_budget
    @mem.remember("relayd_limit", "relayd discards response headers larger than eight kilobytes")
    @mem.remember("long_note", "relayd headers #{'x' * 3000}")
    fill_past_the_summary

    assert_nil @mem.turn_recall("tell me about relayd"), "one shared word recalled an entry"
    recalled = @mem.turn_recall("relayd headers again")
    assert_operator recalled.length, :<=, Master::Ground::Memory::RECALL_CHARS + 80
  end

  class PromptHost
    include Master::Review::Agent::PromptBuilder

    Config = Struct.new(:task_type) do
      def [](_) = nil
    end

    def initialize(memory, messages)
      @memory = memory
      @session = Struct.new(:messages, :topic).new(messages, nil)
      @config = Config.new("code")
    end

    def filter_prompt(text) = text
    def prompt = dynamic_prompt
  end

  def test_the_agent_prompt_carries_recall_for_the_message_being_answered
    @mem.remember("relayd_limit", "relayd discards response headers larger than eight kilobytes")
    fill_past_the_summary
    messages = [{ role: :user, content: "relayd drops response headers" }, { role: :assistant, content: "ok" },
                { role: :user, content: "what about lunch notes" }]

    refute_match(/relayd_limit/, PromptHost.new(@mem, messages).prompt, "recall answered an older message")
    messages << { role: :user, content: "back to relayd response headers" }
    assert_match(/Recalled from memory.*relayd_limit/m, PromptHost.new(@mem, messages).prompt)
  end

  def test_tfidf_recall_finds_relevant_entry
    @mem.remember("ruby_tip", "use frozen_string_literal in all Ruby files")
    @mem.remember("git_tip", "commit frequently with short messages")
    hits = @mem.semantic_recall("frozen string ruby")
    assert hits.any?, "expected TF-IDF hits for ruby query"
    assert hits.first[:key].include?("ruby"), "top hit should be ruby_tip, got #{hits.first[:key]}"
  end

  def test_hybrid_recall_uses_rrf_fusion_for_keyword_vps_mode
    @mem.remember("openbsd_tip", "use rcctl and doas on OpenBSD VPS")
    @mem.remember("rails_tip", "use turbo streams in Rails")

    hits = @mem.hybrid_recall("openbsd rcctl vps", top_n: 2)

    assert hits.any?, "expected hybrid recall hits"
    assert_equal "rrf", hits.first[:fusion]
    assert_equal "openbsd_tip", hits.first[:key]
  end

  def test_fts5_only_recall_works_without_embeddings
    skip "sqlite3 gem unavailable" unless defined?(SQLite3::Database)

    previous_search = ENV["MASTER_MEMORY_SEARCH"]
    previous_zero = ENV["MASTER_ZERO_EMBEDDINGS"]
    ENV["MASTER_MEMORY_SEARCH"] = "fts5"
    ENV["MASTER_ZERO_EMBEDDINGS"] = "1"

    @mem.remember("vps_mode", "OpenBSD VPS memory recall uses FTS5 keyword search")
    @mem.remember("wardrobe", "amber outfit palette and wardrobe notes")

    hits = @mem.semantic_recall("openbsd keyword memory", top_n: 1)

    assert_equal "vps_mode", hits.first[:key]
    assert_equal "fts5", hits.first[:fusion]
  ensure
    ENV["MASTER_MEMORY_SEARCH"] = previous_search
    ENV["MASTER_ZERO_EMBEDDINGS"] = previous_zero
  end

  def test_tfidf_recall_returns_empty_for_noise
    @mem.remember("x", "unrelated content here")
    hits = @mem.semantic_recall("zzzzzzz nonsense 12345")
    assert hits.empty? || hits.all? { |h| h[:score].to_f < 0.1 }
  end

  def test_context_summary_non_empty_after_remember
    @mem.remember("ctx_key", "some important context")
    summary = @mem.context_summary
    refute_nil summary
    assert summary.include?("ctx_key")
  end

  def test_context_summary_cache_invalidates_when_memory_changes
    @mem.remember("first", "alpha")
    first = @mem.context_summary

    @mem.remember("second", "beta")
    second = @mem.context_summary

    assert_includes first, "first"
    refute_includes first, "second"
    assert_includes second, "second"
  end

  def test_context_summary_nil_when_empty
    Dir.mktmpdir("empty_mem_test") do |root|
      mem = Master::Ground::Memory.new(root:)
      without_brain_keys(mem)
      assert_nil mem.context_summary
    end
  end

  def test_all_returns_flat_values
    @mem.remember("k1", "v1")
    @mem.remember("k2", "v2")
    flat = @mem.all
    assert_equal "v1", flat["k1"]
    assert_equal "v2", flat["k2"]
  end

  def test_context_injection_budget_is_bounded_by_model_context
    assert_operator Master::Ground::Memory::MAX_INJECT_TOKENS, :<=, Master::DEFAULT_CONTEXT_WINDOW / 100
  end
end
