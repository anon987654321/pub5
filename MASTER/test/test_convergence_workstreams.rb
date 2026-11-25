# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/convergence/workstreams"

class TestConvergenceWorkstreams < Minitest::Test
  def test_registry_has_unique_ids_and_honest_states
    items = Master::Convergence::Workstreams.items(root: Master::ROOT)
    assert_operator items.size, :>=, 20
    assert_equal items.map { |item| item[:id] }.uniq.size, items.size
    items.each { |item| assert_includes Master::Convergence::STATES.map(&:to_s), item[:state] }
  end

  def test_implementation_presence_checks_every_concrete_path_in_the_requested_checkout
    Dir.mktmpdir do |repository|
      root = File.join(repository, "MASTER")
      FileUtils.mkdir_p(root)
      FileUtils.mkdir_p(File.join(repository, "BIZ"))
      File.write(File.join(root, "source.rb"), "VALUE = 1\n")
      workstreams = Master::Convergence::Workstreams

      assert workstreams.path_present?(root, "MASTER/source.rb; BIZ")
      assert workstreams.path_present?(root, "MASTER/source.rb + BIZ")
      refute workstreams.path_present?(root, "MASTER/source.rb; RAILS")
      refute workstreams.path_present?(root, "MASTER/source.rb; MASTER/missing.rb")
      refute workstreams.path_present?(root, "BIZ templates")
      refute workstreams.path_present?(root, "MASTER/../BIZ")
      File.symlink(File.dirname(repository), File.join(root, "external"))
      refute workstreams.path_present?(root, "MASTER/external")
    end
  end

  def test_render_can_filter_one_workstream
    result = Master::Convergence::Workstreams.render("snapshot_exchange", root: Master::ROOT)
    assert_includes result, "snapshot_exchange"
    assert_includes result, "share-safe"
  end

  # The architecture review names two rows that now have source and focused
  # proof, but their current pinned-host test acceptance remains unverified.
  IMPLEMENTED_UNVERIFIED = %w[inconclusive_aging constitution_self_budget documentation_completeness].freeze
  REVIEW_DESIGN_OF_RECORD = %w[ops_alert_channel].freeze

  def test_implemented_review_rows_remain_partial_until_current_host_proof_runs
    items = Master::Convergence::Workstreams.items(root: Master::ROOT)
    rows = IMPLEMENTED_UNVERIFIED.map { |id| items.find { |item| item[:id] == id } }

    rows.each do |row|
      refute_nil row, "an implemented workstream was deleted from convergence.yml"
      assert_equal "partial", row[:state], "#{row[:id]} has source/tests but remains unverified here"
      refute_empty row[:implementation], "#{row[:id]} names no implementation"
      refute_empty row[:proof], "#{row[:id]} names no proof"
    end
  end

  def test_unimplemented_review_rows_stay_missing_until_their_proof_exists
    items = Master::Convergence::Workstreams.items(root: Master::ROOT)
    rows = REVIEW_DESIGN_OF_RECORD.map { |id| items.find { |item| item[:id] == id } }

    rows.each do |row|
      refute_nil row, "a review design-of-record row was deleted from convergence.yml"
      assert_equal "missing", row[:state], "#{row[:id]} leaves missing only in the commit that adds its proof"
      refute_empty row[:implementation], "#{row[:id]} names no implementation"
      refute_empty row[:proof], "#{row[:id]} names no proof"
    end
  end
end
