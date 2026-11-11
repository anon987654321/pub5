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

  def test_async_index_build_slot_is_released_for_a_later_refresh
    with_tree do |root|
      index = Index.new(root:)
      index.build_async
      index.wait_for_build
      assert_nil index.instance_variable_get(:@build_thread)

      File.write(File.join(root, "a.rb"), "class Refreshed; end\n")
      index.build_async
      index.wait_for_build

      assert index.complete?
      assert index.lookup("Refreshed")
      assert_nil index.instance_variable_get(:@build_thread)
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

  def test_mixin_relationships_survive_persistent_code_index_restore
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "mixins.rb"), <<~RUBY)
        module IncludedMethods; end
        module PriorityMethods; end
        class Widget
          include IncludedMethods
          prepend PriorityMethods
        end
      RUBY

      cold = Index.new(root:, persist: true).build
      expected = ["include:IncludedMethods", "prepend:PriorityMethods"]
      assert_equal expected, cold.query("Widget").first.fetch(:includes)
      assert_includes cold.summary, "[include:IncludedMethods, prepend:PriorityMethods]"

      warm = Index.new(root:, persist: true).build
      assert_equal expected, warm.query("Widget").first.fetch(:includes)
      assert_equal cold.summary, warm.summary
    end
  end

  def test_public_symbol_and_reference_views_cannot_mutate_the_live_graph
    with_tree do |root|
      cold = Index.new(root:, persist: true).build
      warm = Index.new(root:, persist: true).build

      [cold, warm].each do |index|
        symbols = index.symbols
        references = index.references
        assert_predicate symbols, :frozen?
        assert_predicate references, :frozen?
        assert_raises(FrozenError) { symbols.clear }
        assert_raises(FrozenError) { references.clear }

        symbol = symbols.find { |row| row.fqn == "Alpha#one" }
        assert_predicate symbol, :frozen?
        assert_predicate symbol.fqn, :frozen?
        assert_predicate symbol.includes, :frozen?
        assert_raises(FrozenError) { symbol.fqn.replace("Corrupted") }
        assert_raises(FrozenError) { symbol.includes << "Corrupted" }

        reference = references.first
        assert_predicate reference, :frozen?
        assert_predicate reference.to_fqn, :frozen?
        assert_raises(FrozenError) { reference.to_fqn.replace("Corrupted") }
        assert_equal ["a.rb", 2], index.lookup("Alpha#one")
        assert index.complete?
      end
    end
  end

  def test_errors_are_immutable_snapshots
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "broken.rb"), "def unfinished(\n")
      index = Index.new(root:).build

      errors = index.errors
      assert_predicate errors, :frozen?
      assert_predicate errors.first, :frozen?
      assert_predicate errors.first.fetch(:message), :frozen?
      assert_raises(FrozenError) { errors.first.fetch(:message).replace("hidden") }
      assert_equal "broken.rb", errors.first.fetch(:path)
      assert_equal :parse, errors.first.fetch(:kind)
      assert_includes index.errors.first.fetch(:message), "unexpected"
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
      File.write(File.join(outside, "private.rb"), "class OutsideSecret; end\n")
      File.symlink(File.join(outside, "private.rb"), File.join(root, "leak.rb"))

      index = Index.new(root:, persist: true).build

      refute index.complete?
      assert_nil index.lookup("OutsideSecret")
      assert_equal :read, index.errors.fetch(0).fetch(:kind)
      refute File.exist?(Master::Review::CodeIndexStore.new(root:).path)
    end
  end

  def test_hardlinked_ruby_source_is_not_indexed
    Dir.mktmpdir do |directory|
      root = File.join(directory, "root")
      outside = File.join(directory, "outside")
      Dir.mkdir(root)
      Dir.mkdir(outside)
      external = File.join(outside, "private.rb")
      File.write(external, "class ExternalPrivateSource; end\n")
      File.link(external, File.join(root, "linked.rb"))

      index = Index.new(root:).build

      refute index.complete?
      assert_nil index.lookup("ExternalPrivateSource")
      assert_equal :read, index.errors.fetch(0).fetch(:kind)
      assert_equal 2, File.stat(external).nlink
    end
  end

  def test_source_changed_during_parse_is_not_recorded_as_current
    with_tree do |root|
      path = File.join(root, "a.rb")
      original_parse = Prism.method(:parse)
      Prism.define_singleton_method(:parse) do |source, *arguments|
        File.write(path, "class Replaced; end\n") if source.include?("class Alpha")
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

  def test_scoped_rebuild_preserves_symbols_and_errors_outside_its_scope
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "outside.rb"), "class Outside; end\n")
      Dir.mkdir(File.join(root, "lib"))
      File.write(File.join(root, "lib", "inside.rb"), "class Inside; end\n")
      index = Index.new(root:).build

      File.write(File.join(root, "lib", "inside.rb"), "class RevisedInside; end\n")
      index.build(path: "lib")

      assert index.partial?
      assert index.lookup("Outside"), "a scoped rebuild must retain out-of-scope symbols"
      assert index.lookup("RevisedInside")
      assert_nil index.lookup("Inside")

      File.write(File.join(root, "outside.rb"), "def incomplete(\n")
      index.build
      assert_equal :parse, index.errors.find { |entry| entry[:path] == "outside.rb" }.fetch(:kind)

      File.write(File.join(root, "lib", "inside.rb"), "class FinalInside; end\n")
      index.build(path: "lib")
      assert_equal :parse, index.errors.find { |entry| entry[:path] == "outside.rb" }.fetch(:kind),
                   "a scoped success must not erase an out-of-scope parse failure"
      assert index.lookup("FinalInside")
    end
  end

  def test_scoped_build_refuses_a_symlinked_directory
    Dir.mktmpdir do |directory|
      root = File.join(directory, "root")
      outside = File.join(directory, "outside")
      Dir.mkdir(root)
      Dir.mkdir(outside)
      File.write(File.join(outside, "secret.rb"), "class SecretOutside; end\n")
      File.symlink(outside, File.join(root, "linked"))

      index = Index.new(root:).build(path: "linked")

      refute index.complete?
      assert_equal :build, index.errors.fetch(0).fetch(:kind)
      assert_nil index.lookup("SecretOutside")
    end
  end

  def test_scoped_build_cannot_escape_the_repository_root
    Dir.mktmpdir do |directory|
      root = File.join(directory, "root")
      outside = File.join(directory, "outside")
      Dir.mkdir(root)
      Dir.mkdir(outside)
      File.write(File.join(outside, "secret.rb"), "class SecretOutside; end\n")

      index = Index.new(root:)

      assert_same index, index.build(path: "../outside")
      refute index.complete?
      assert_equal :build, index.errors.fetch(0).fetch(:kind)
      assert_nil index.lookup("SecretOutside")
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

  def test_group_or_world_readable_snapshot_is_ignored_and_rebuilt
    with_tree do |root|
      Index.new(root:, persist: true).build
      store = Master::Review::CodeIndexStore.new(root:)
      File.chmod(0o644, store.path)

      parsed_files do |parsed|
        rebuilt = Index.new(root:, persist: true).build
        assert_equal %w[Alpha Beta], parsed.sort
        assert rebuilt.complete?
        assert_equal 0o600, File.stat(store.path).mode & 0o777
      end
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

  def test_structurally_invalid_snapshot_falls_back_to_a_full_build
    with_tree do |root|
      Index.new(root:, persist: true).build
      store = Master::Review::CodeIndexStore.new(root:)
      data = JSON.parse(File.read(store.path))
      data["symbols"] = nil
      File.write(store.path, JSON.generate(data))

      parsed_files do |parsed|
        rebuilt = Index.new(root:, persist: true).build
        assert_equal %w[Alpha Beta], parsed.sort
        assert rebuilt.complete?
        assert rebuilt.lookup("Beta#two")
      end
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
