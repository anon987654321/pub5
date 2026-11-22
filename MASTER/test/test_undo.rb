# frozen_string_literal: true

require "tmpdir"
require "json"
require "fileutils"
require_relative "test_helper"

class TestUndo < Minitest::Test
  Session = Struct.new(:snapshots) do
    def snapshot(path, content)
      snapshots << [path, content]
    end
  end

  def test_undo_restores_the_previous_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      undo = Master::Trace::Undo.new(session: Session.new([]), root: dir)

      assert undo.snapshot(path).ok?
      File.write(path, "after")

      result = undo.undo!

      assert result.ok?
      assert_equal "before", File.read(path)
    end
  end

  def test_separate_undo_instances_merge_snapshots_instead_of_overwriting
    Dir.mktmpdir do |dir|
      first_path = File.join(dir, "first.txt")
      second_path = File.join(dir, "second.txt")
      File.write(first_path, "first before")
      File.write(second_path, "second before")
      first = Master::Trace::Undo.new(session: Session.new([]), root: dir)
      second = Master::Trace::Undo.new(session: Session.new([]), root: dir)

      assert first.snapshot(first_path).ok?
      assert second.snapshot(second_path).ok?

      journal = File.readlines(File.join(dir, ".master", "undo_journal.jsonl")).map { |line| JSON.parse(line) }
      assert_equal [first_path, second_path], journal.map { |entry| entry.fetch("path") }
    end
  end

  def test_undo_removes_a_file_that_did_not_exist_before_the_write
    Dir.mktmpdir do |dir|
      path = File.join(dir, "new.txt")
      undo = Master::Trace::Undo.new(session: Session.new([]), root: dir)

      assert undo.snapshot(path).ok?
      File.write(path, "created")

      result = undo.undo!

      assert result.ok?
      refute File.exist?(path)
    end
  end

  def test_prune_rewrites_only_the_latest_entries_and_secures_private_state
    Dir.mktmpdir do |dir|
      state_dir = File.join(dir, ".master")
      FileUtils.mkdir_p(state_dir)
      File.chmod(0o755, state_dir)
      journal_path = File.join(state_dir, "undo_journal.jsonl")
      entries = Array.new(Master::Trace::Undo::MAX_JOURNAL + 3) do |index|
        { "path" => "file-#{index}", "content" => "before-#{index}", "ts" => index }
      end
      File.write(journal_path, entries.map { |entry| JSON.generate(entry) + "\n" }.join)
      File.chmod(0o644, journal_path)

      undo = Master::Trace::Undo.new(session: Session.new([]), root: dir)

      assert_equal 0o700, File.stat(state_dir).mode & 0o777
      assert_equal 3, undo.prune!

      retained = File.readlines(journal_path).map { |line| JSON.parse(line) }
      assert_equal Master::Trace::Undo::MAX_JOURNAL, retained.size
      assert_equal "file-3", retained.first.fetch("path")
      assert_equal "before-3", retained.first.fetch("content")
      assert_equal "file-#{entries.size - 1}", retained.last.fetch("path")
      assert_equal "before-#{entries.size - 1}", retained.last.fetch("content")
      assert_equal 0, File.stat(journal_path).mode & 0o077
    end
  end

  def test_prune_reloads_snapshots_written_by_another_instance
    Dir.mktmpdir do |dir|
      first_path = File.join(dir, "first.txt")
      second_path = File.join(dir, "second.txt")
      File.write(first_path, "first before")
      File.write(second_path, "second before")
      first = Master::Trace::Undo.new(session: Session.new([]), root: dir)
      second = Master::Trace::Undo.new(session: Session.new([]), root: dir)

      assert first.snapshot(first_path).ok?
      assert second.snapshot(second_path).ok?
      assert_equal 0, first.prune!

      journal = File.readlines(File.join(dir, ".master", "undo_journal.jsonl")).map { |line| JSON.parse(line) }
      assert_equal [first_path, second_path], journal.map { |entry| entry.fetch("path") }
    end
  end

end
