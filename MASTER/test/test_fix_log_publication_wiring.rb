# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../lib/fix/fix_loop"
require_relative "../lib/fix/log_publication"

# The /fix terminal path must publish the run's logs to a gist/pastebin after
# each run and record the receipt where an operator can find it later. These
# tests drive the Completion wiring directly on an allocated loop; the HTTP
# layer itself is covered by test_log_publication.rb.
class FixLogPublicationWiringTest < Minitest::Test
  CompletionSource = File.read(File.expand_path("../lib/fix/fix_loop/completion.rb", __dir__))

  KernelDouble = Struct.new(:log_path)

  JournalDouble = Struct.new(:rows) do
    def history(limit:) = rows.first(limit)
  end

  def loop_with(kernel: nil, journal: nil)
    loop = Master::Fix::FixLoop.allocate
    loop.instance_variable_set(:@kernel, kernel)
    loop.instance_variable_set(:@run_journal, journal)
    loop
  end

  def test_terminal_path_records_publication_before_the_journal_write
    terminal_at = CompletionSource.index("@run_journal.terminal(run_id")
    publication_at = CompletionSource.index("evidence[:log_publication] = publish_run_log(")

    refute_nil publication_at, "finish_run must publish the run log"
    refute_nil terminal_at, "finish_run must still write the journal terminal row"
    assert publication_at < terminal_at,
           "the publication receipt must land in the durable journal evidence, not evaporate with the terminal"
    assert_includes CompletionSource, "outcome[:log_publication] = evidence[:log_publication]"
  end

  def test_kernel_events_select_only_the_run_and_skip_garbage
    Dir.mktmpdir do |dir|
      path = File.join(dir, "log.jsonl")
      rows = [
        { "seq" => 1, "run_id" => "run-a", "kind" => "run_started", "payload" => {} },
        { "seq" => 2, "run_id" => "run-b", "kind" => "run_started", "payload" => {} },
        { "seq" => 3, "run_id" => "run-a", "kind" => "run_terminal", "payload" => { "state" => "done" } },
      ]
      File.write(path, rows.map { |row| JSON.generate(row) }.join("\n") + "\n{corrupt\n")

      events = loop_with(kernel: KernelDouble.new(path))
               .send(:kernel_events_for, "run-a")

      assert_equal 2, events.size
      assert events.all? { |line| JSON.parse(line)["run_id"] == "run-a" }
      assert_equal %w[run_started run_terminal], events.map { |line| JSON.parse(line)["kind"] }
    end
  end

  def test_kernel_events_absent_kernel_or_log
    assert_empty loop_with(kernel: nil).send(:kernel_events_for, "run-a")
    assert_empty loop_with(kernel: KernelDouble.new("/nonexistent/log.jsonl")).send(:kernel_events_for, "run-a")
  end

  def test_run_log_text_carries_header_events_and_journal_record
    Dir.mktmpdir do |dir|
      path = File.join(dir, "log.jsonl")
      File.write(path, JSON.generate({ "run_id" => "run-9", "kind" => "run_started", "payload" => {} }) + "\n")
      journal = JournalDouble.new([{ "id" => "run-9", "state" => "running", "passes" => [] }])

      text = loop_with(kernel: KernelDouble.new(path), journal:)
             .send(:run_log_text, run_id: "run-9", target: "MASTER", state: :done, message: "clean")

      assert_includes text, "run_id: run-9"
      assert_includes text, "terminal_state: done"
      assert_includes text, "== kernel ledger events (1) =="
      assert_includes text, '"kind":"run_started"'
      assert_includes text, '"state": "running"'
      assert_includes text, "== run journal record =="
    end
  end

  def test_publish_run_log_returns_receipt_and_never_raises
    receipt = Master::Fix::LogPublication::Result.new(sink: "gist", url: "https://gist.github.com/x/y", redacted: true)
    loop = loop_with(kernel: nil, journal: JournalDouble.new([]))

    captured = nil
    Master::Fix::LogPublication.stub(:publish, ->(**kwargs) { captured = kwargs; receipt }) do
      result = loop.send(:publish_run_log, run_id: "run-1", target: "MASTER", state: :done, message: "clean")
      assert_equal receipt, result
    end
    assert_equal "run-1", captured[:run_id]
    assert_includes captured[:log_text], "run_id: run-1"
  end

  def test_publish_run_log_swallows_publication_crash
    loop = loop_with(kernel: nil, journal: JournalDouble.new([]))

    Master::Fix::LogPublication.stub(:publish, ->(**) { raise IOError, "disk gone" }) do
      result = loop.send(:publish_run_log, run_id: "run-1", target: "MASTER", state: :blocked, message: "gaps")
      assert_nil result.sink
      assert_match(/IOError: disk gone/, result.error)
    end
  end

  def test_publish_run_log_under_proof_env_skips_cleanly
    # The suite itself runs with MASTER_IN_PROOF=1, so the real publisher takes
    # the skip path here — proving the fail-soft receipt shape end to end
    # without any network.
    loop = loop_with(kernel: nil, journal: JournalDouble.new([]))
    result = loop.send(:publish_run_log, run_id: "run-1", target: "MASTER", state: :done, message: "clean")

    assert_nil result.sink
    assert_match(/MASTER_IN_PROOF/, result.skipped)
  end
end
