# frozen_string_literal: true

require_relative "test_helper"

class TestCodeIndexStore < Minitest::Test
  Index = Master::Review::CodeIndex

  def with_tree
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "a.rb"), "class Alpha\n  def one = 1\nend\n")
      File.write(File.join(root, "b.rb"), "class Beta\n  def two = Alpha.new.one\nend\n")
      yield root
    end
  end

  # Counts the files Prism parses, which is the cost the snapshot exists to skip.
  def parsed_files
    parsed = []
    original = Prism.method(:parse)
    Prism.define_singleton_method(:parse) { |src, *rest| parsed << src[/class (\w+)/, 1] and original.call(src, *rest) }
    yield parsed
  ensure
    Prism.define_singleton_method(:parse, original)
  end

  def test_repeated_async_build_requests_share_the_active_build
    with_tree do |root|
      entered = Queue.new
      release = Queue.new
      original_parse = Prism.method(:parse)
      count = 0
      Prism.define_singleton_method(:parse) do |source, *arguments|
        count += 1
        entered << true
        release.pop
        original_parse.call(source, *arguments)
      end

      index = Index.new(root:)
      index.build_async
      entered.pop
      active = index.instance_variable_get(:@build_thread)
      index.build_async

      assert_same active, index.instance_variable_get(:@build_thread)
      release << true
      index.wait_for_build
      assert index.complete?
      assert_equal 1, count
    ensure
      release << true if release
      Prism.define_singleton_method(:parse, original_parse) if original_parse
      index&.wait_for_build
    end
  end

  def test_warm_boot_parses_nothing_and_answers_the_same
    with_tree do |root|
      cold = Index.new(root:, persist: true).build
      parsed_files do |parsed|
        warm = Index.new(root:, persist: true).build

        assert_empty parsed
        assert_equal cold.size, warm.size
        assert_equal cold.lookup("Alpha#one"), warm.lookup("Alpha#one")
        assert_equal cold.impact("Alpha#one")[:reference_count], warm.impact("Alpha#one")[:reference_count]
      end
    end
  end

  def test_only_the_changed_file_is_reparsed_and_its_old_symbols_go
    with_tree do |root|
      Index.new(root:, persist: true).build
      File.write(File.join(root, "a.rb"), "class Alpha\n  def renamed_method = 1\n  def extra = 2\nend\n")
      parsed_files do |parsed|
        warm = Index.new(root:, persist: true).build

        assert_equal ["Alpha"], parsed
        assert warm.lookup("Alpha#renamed_method")
        assert_nil warm.lookup("Alpha#one")
      end
    end
  end

  def test_same_size_edit_with_preserved_mtime_is_reparsed
    with_tree do |root|
      Index.new(root:, persist: true).build
      path = File.join(root, "a.rb")
      before = File.stat(path)
      replacement = "class Alpha\n  def two = 2\nend\n"
      assert_equal before.size, replacement.bytesize
      File.write(path, replacement)
      File.utime(before.atime, before.mtime, path)
      after = File.stat(path)
      assert_equal before.mtime, after.mtime
      assert_equal before.size, after.size

      parsed_files do |parsed|
        warm = Index.new(root:, persist: true).build
        assert_equal ["Alpha"], parsed
        assert warm.lookup("Alpha#two")
        assert_nil warm.lookup("Alpha#one")
      end
    end
  end

  def test_reopened_definitions_are_retained_across_files_and_snapshots
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "part_a.rb"), "module Shared\n  class Widget; end\nend\n")
      File.write(File.join(root, "part_b.rb"), "module Shared\n  class Widget; end\n")

      index = Index.new(root:, persist: true).build
      definitions = index.find("Shared::Widget").select { |symbol| symbol.type == :class }
      assert_equal 2, definitions.size
      assert_equal %w[part_a.rb part_b.rb], definitions.map { |symbol| File.basename(symbol.file) }.sort

      warm = Index.new(root:, persist: true).build
      warm_definitions = warm.find("Shared::Widget").select { |symbol| symbol.type == :class }
      assert_equal 2, warm_definitions.size
    end
  end

  def test_a_never_built_index_is_not_complete
    Dir.mktmpdir do |root|
      index = Index.new(root:)
      refute index.built?
      refute index.complete?
    end
  end

  def test_symlinked_ruby_source_outside_the_root_is_not_indexed
    Dir.mktmpdir do |directory|
      root = File.join(directory, "root")
      outside = File.join(directory, "outside")
      Dir.mkdir(root)
      Dir.mkdir(outside)
      File.write(File.join(outside, "private.rb"), "class OutsideSecret; end\\n")
      File.symlink(File.join(outside, "private.rb"), File.join(root, "leak.rb"))

      index = Index.new(root:, persist: true).build

      refute index.complete?
      assert_nil index.lookup("OutsideSecret")
      assert_equal :read, index.errors.fetch(0).fetch(:kind)
      refute File.exist?(Master::Review::CodeIndexStore.new(root:).path)
    end
  end

  def test_source_changed_during_parse_is_not_recorded_as_current
    with_tree do |root|
      path = File.join(root, "a.rb")
      original_parse = Prism.method(:parse)
      Prism.define_singleton_method(:parse) do |source, *arguments|
        File.write(path, "class Replaced; end\\n") if source.include?("class Alpha")
        original_parse.call(source, *arguments)
      end
      index = Index.new(root:, persist: true).build

      refute index.complete?
      assert_nil index.lookup("Alpha")
      assert_equal :changed, index.errors.find { |entry| entry[:path] == "a.rb" }.fetch(:kind)
      refute File.exist?(Master::Review::CodeIndexStore.new(root:).path)
    ensure
      Prism.define_singleton_method(:parse, original_parse) if original_parse
    end
  end

  def test_deleted_file_is_purged_from_the_snapshot
    with_tree do |root|
      Index.new(root:, persist: true).build
      File.delete(File.join(root, "b.rb"))

      assert_nil Index.new(root:, persist: true).build.lookup("Beta#two")
    end
  end

  def test_path_scoped_build_is_not_claimed_as_a_complete_index
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "root.rb"), "class RootOnly; end\n")
      Dir.mkdir(File.join(root, "lib"))
      File.write(File.join(root, "lib", "nested.rb"), "class Nested; end\n")
      index = Index.new(root:).build(path: "lib")

      assert index.partial?
      refute index.complete?
      index.build
      refute index.partial?
      assert index.complete?
      assert index.lookup("RootOnly")
    end
  end

  def test_parse_failures_are_visible_and_never_saved_as_complete_snapshots
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      path = File.join(root, "broken.rb")
      File.write(path, "def incomplete(\n")
      index = Index.new(root:, persist: true).build
      store = Master::Review::CodeIndexStore.new(root:)

      refute index.complete?
      assert_equal "broken.rb", index.errors.fetch(0).fetch(:path)
      assert_equal :parse, index.errors.fetch(0).fetch(:kind)
      refute File.exist?(store.path), "an incomplete graph must not become a warm snapshot"

      File.write(path, "module Recovered\n  def self.ok = true\nend\n")
      index.build
      assert index.complete?
      assert_empty index.errors
      assert index.lookup("Recovered.ok")
      assert File.file?(store.path)
    end
  end

  def test_a_snapshot_from_other_parsing_logic_is_rejected
    with_tree do |root|
      Index.new(root:, persist: true).build
      store = Master::Review::CodeIndexStore.new(root:)
      data = JSON.parse(File.read(store.path))
      data["stamp"] = [0, "old", "old"]
      File.write(store.path, JSON.generate(data))

      parsed_files do |parsed|
        Index.new(root:, persist: true).build
        assert_equal %w[Alpha Beta], parsed.sort
      end
    end
  end

  def test_persisted_snapshot_is_private
    with_tree do |root|
      Index.new(root:, persist: true).build
      store = Master::Review::CodeIndexStore.new(root:)

      assert File.file?(store.path)
      assert_equal 0o600, File.stat(store.path).mode & 0o777
    end
  end

  def test_symlinked_cache_directory_is_refused_without_writing_outside
    with_tree do |root|
      outside = File.join(File.dirname(root), "code-index-outside-#{SecureRandom.hex(4)}")
      Dir.mkdir(outside)
      File.symlink(outside, File.join(root, ".master"))

      index = Index.new(root:, persist: true).build
      store = Master::Review::CodeIndexStore.new(root:)

      assert index.complete?, "cache availability must not change the in-memory scan result"
      refute File.exist?(File.join(outside, "code_index"))
      refute File.exist?(store.path)
    end
  end

  def test_without_persist_nothing_is_written
    with_tree do |root|
      Index.new(root:).build

      refute File.exist?(File.join(root, ".master"))
    end
  end

  def test_a_corrupt_snapshot_falls_back_to_a_full_build
    with_tree do |root|
      Index.new(root:, persist: true).build
      File.write(Master::Review::CodeIndexStore.new(root:).path, "{not json")

      assert Index.new(root:, persist: true).build.lookup("Beta#two")
    end
  end
end

class TestCodeIndexSummaryMemo < Minitest::Test
  def test_summary_orientation_is_stable_then_follows_a_reindex
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "a.rb"), "class Alpha\nend\n")
      index = Master::Review::CodeIndex.new(root:).build

      assert_equal index.summary, index.summary
      before = index.summary
      File.write(File.join(root, "b.rb"), "class Beta\nend\n")
      index.reindex(File.join(root, "b.rb"))

      refute_equal before, index.summary
      assert_includes index.summary, "2 symbols"
    end
  end
end
