# frozen_string_literal: true

require_relative "fix_helper"

# The incremental scan and its tree key, moved from pub4
# MASTER/test/test_ratchet_cache.rb (fe241a94cf): an unchanged tree answers
# at once, an edit rescans only its file, and an untracked file counts.
class FixScanTest < Minitest::Test
  include FixHelper

  def scan(world, scope = ".") = Fix::Scan.new(world:, laws: [violation_law], scope:)

  def test_an_unchanged_tree_answers_from_the_cache_and_an_edit_rescans_one_file
    repo do |root|
      put(root, "a.rb", "violation\n")
      put(root, "b.rb", "fine\n")
      commit_all(root)
      world = fix_world(root)

      first = scan(world).call
      again = scan(world).call
      put(root, "b.rb", "violation\nviolation\n")
      edited = scan(world).call

      assert_equal [3, 1, false], [first.scanned, first.findings.size, first.cached_tree]
      assert again.cached_tree
      assert_equal first.findings, again.findings
      assert_equal [1, 3], [edited.scanned, edited.findings.size]
    end
  end

  def test_the_tree_key_moves_with_a_commit_an_edit_and_an_untracked_file
    repo do |root|
      put(root, "a.rb", "a\n")
      commit_all(root)
      world = fix_world(root)
      keys = [Fix::TreeDigest.key(world, ".")]
      put(root, "a.rb", "b\n")
      keys << Fix::TreeDigest.key(world, ".")
      put(root, "new.rb", "c\n")
      keys << Fix::TreeDigest.key(world, ".")
      commit_all(root, "Add the new file")
      keys << Fix::TreeDigest.key(world, ".")

      assert_equal 4, keys.uniq.size
      assert_equal keys.last, Fix::TreeDigest.key(world, ".")
    end
  end

  def test_a_scope_reads_only_its_tree
    repo do |root|
      put(root, "lib/a.rb", "violation\n")
      put(root, "other/b.rb", "violation\n")
      commit_all(root)

      assert_equal ["lib/a.rb"], scan(fix_world(root), "lib").call.findings.map(&:file)
    end
  end

  def test_focus_picks_one_scanning_law_and_refuses_an_unknown_id
    laws = [violation_law, violation_law(:OTHER)]
    assert_equal [:OTHER], Fix::Scan.scanning(laws, focus: "OTHER").map(&:id)
    assert_raises(ArgumentError) { Fix::Scan.scanning(laws, focus: "NOPE") }
  end
end
