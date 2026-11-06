# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../master/memory/memory"

# Moved from pub4 test_memory.rb. Not movable: the reasoning and preference
# frames, embeddings, FTS5 and RRF fusion (their code was not moved: it
# needed Cognition::Intelligence, Review::Embeddings and the sqlite3 gem);
# the visitor guard (pub5 has no web visitor yet); the legacy YAML store;
# the PromptBuilder case, which is test/cli's conversation test here.
class MemoryTest < Minitest::Test
  include TestHelper

  def setup
    @now = 1_800_000_000
    @dir = Dir.mktmpdir("pub5-memory")
    @root = File.realpath(@dir)
    @world = world(@root, { read: ["log/master/*"], write: ["log/master/*"] })
    @mem = fresh
  end

  def teardown = FileUtils.remove_entry(@dir)

  def fresh = Memory::Store.new(world: @world, clock: -> { @now += 1 })

  def test_remember_and_recall
    @mem.remember("test_key", "hello world")
    assert_equal "hello world", @mem.recall("test_key")
  end

  def test_forget_removes_archived_copy_and_conflict_history
    @mem.remember("deadline", "Friday", source: "conversation:1", confidence: 0.8)
    @mem.remember("deadline", "Monday", source: "conversation:2", confidence: 0.7)
    assert_equal 1, @mem.conflicts_for("deadline").size

    @mem.forget("deadline")

    assert_nil @mem.recall("deadline")
    assert_empty @mem.conflicts_for("deadline")
    assert_nil fresh.recall("deadline"), "forgetting is persisted"
  end

  def test_type_filtering_and_counts
    @mem.remember("a", "engineer", type: "user")
    @mem.remember("b", "two", type: "user")
    @mem.remember("c", "deadline friday", type: "project")

    assert_equal %w[a b], @mem.by_type("user").keys
    assert_equal({ "user" => 2, "project" => 1 }, @mem.type_counts)
  end

  def test_persistence_survives_reload_and_is_owner_only
    @mem.remember("persist_key", "i survived", type: "reference")

    assert_equal "i survived", fresh.recall("persist_key")
    assert_equal 0o600, File.stat(File.join(@root, Memory::Store::PATH)).mode & 0o777
  end

  def test_new_memory_has_provenance_with_explicit_source_and_confidence
    @mem.remember("provenance", "captured", type: "user", source: "conversation:42", confidence: 0.9)

    assert_equal ["conversation:42", 0.9], @mem.provenance("provenance").values_at("source", "confidence")
  end

  def test_conflicting_memory_is_preserved_with_both_provenances
    @mem.remember("deadline", "Friday", source: "conversation:1")
    @mem.remember("deadline", "Monday", source: "conversation:2")
    conflict = @mem.conflicts_for("deadline").first

    assert_equal "Monday", @mem.recall("deadline")
    assert_equal %w[Friday Monday], conflict.values_at("previous", "incoming")
    assert_equal "conversation:1", conflict.dig("previous_provenance", "source")
  end

  def test_auto_save_patterns_and_idempotence
    assert @mem.auto_save("I'm a senior Ruby engineer at a startup").start_with?("auto/user/")
    first = @mem.auto_save("never use awk in zsh scripts, use parameter expansion instead")
    assert first.start_with?("auto/feedback/")
    assert_equal first, @mem.auto_save("never use awk in zsh scripts, use parameter expansion instead")
    assert_equal 1, @mem.by_type("feedback").size
    assert_nil @mem.auto_save("the weather is grey")
  end

  # Twelve user entries take every slot of the summary, which orders user
  # first: the store is too big to inject whole, the case recall exists for.
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
    assert_operator @mem.turn_recall("relayd headers again").length, :<=, Memory::Store::RECALL_CHARS + 80
  end

  def test_keyword_recall_finds_the_relevant_entry_and_ignores_noise
    @mem.remember("ruby_tip", "use frozen_string_literal in all Ruby files")
    @mem.remember("git_tip", "commit frequently with short messages")

    assert_equal "ruby_tip", @mem.keyword_recall("frozen string ruby").first[:key]
    assert_empty @mem.keyword_recall("zzzzzzz nonsense 12345")
  end

  def test_context_summary_follows_the_store_and_is_nil_when_empty
    assert_nil @mem.context_summary
    @mem.remember("first", "alpha")
    first = @mem.context_summary
    @mem.remember("second", "beta")

    assert_includes first, "first"
    refute_includes first, "second"
    assert_includes @mem.context_summary, "second"
    assert_operator Memory::Store::MAX_INJECT_CHARS / 4, :<=, 2_000, "the summary stays inside 2,000 tokens"
  end

  def test_consolidation_archives_old_entries_and_keeps_a_summary
    @mem.remember("old", "from long ago")
    @now += 400 * Memory::Store::SECONDS_PER_DAY
    @mem.remember("new", "from today")
    line = @mem.consolidate!(summarise: ->(prompt) { "summary of #{prompt.lines.size - 1} entries" })

    assert_equal "memory0: 2 entries checked, 1 archived", line
    assert_nil @mem.all["old"]
    assert_equal "summary of 1 entries", @mem.recall("_consolidated_summary")
    assert_includes @mem.context_summary, "[+1 archived]"
  end
end
