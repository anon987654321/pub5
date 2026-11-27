# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestLawsReflow < Minitest::Test
  def test_nine_invariant_nodes_follow_document_order
    data = Master.load_yaml(File.join(Master::ROOT, "data", "laws.yml"))
    node_ids = data.filter_map { |id, row| id if row.is_a?(Hash) && row["node"] }

    assert_equal 9, node_ids.size
    assert_equal Master::Soul.invariant_order.map(&:upcase), node_ids
    assert_operator data.keys.index("SACRED_AUTHORSHIP"), :>, data.keys.index(node_ids.last)
  end

  def test_laws_yml_is_a_valid_self_governing_flat_catalogue
    data = YAML.safe_load_file(File.join(Master::ROOT, "data", "laws.yml"), aliases: true)

    assert_kind_of Hash, data
    assert Master::FlatLawCatalogue.validate!(data)
  end

  def test_catalogue_has_no_retired_numeric_ranking_or_path_scope
    data = YAML.safe_load_file(File.join(Master::ROOT, "data", "laws.yml"), aliases: false)
    assert_empty retired_fields(data)
  end

  def test_retired_fields_check_distinguishes_law_policy_from_runtime_configuration
    data = {
      "EXAMPLE" => { "statement" => "A rule", "root" => "no_surplus", "priority" => 1 },
      "law_catalogue" => { "defaults" => { "tier" => 2 }, "entries" => {
        "EXAMPLE" => { "path" => "lib", "path_exclude" => "test" },
      } },
      "runtime" => { "path" => "MASTER", "applies_to" => ["MASTER"] },
    }

    assert_equal(
      { "EXAMPLE" => ["priority"], "defaults" => ["tier"], "entries.EXAMPLE" => ["path"] },
      retired_fields(data),
    )
  end

  def test_governing_and_famous_laws_precede_the_invariant_details
    data = Master.load_yaml(File.join(Master::ROOT, "data", "laws.yml"))
    ids = Master::FlatLawCatalogue.entries(data).map { |row| row.fetch("id") }
    assert_equal %w[APPLICATION_IS_UNIFORM PRESERVE_FIRST DO_THE_WORK_NOW DRY KISS], ids.first(5)
    first_node = ids.index("TRUTHFUL_STATUS")

    Master::FlatLawCatalogue::FAMOUS_NAMES.each do |id|
      assert_operator ids.index(id), :<, first_node, id
    end
  end

  def test_named_heuristic_families_keep_individual_law_identities
    data = Master.laws_document
    named = Master::FlatLawCatalogue.entries(data).map { |row| row.fetch("id") }
    first_node = named.index("TRUTHFUL_STATUS")
    heuristics = %w[SYSTEM_STATUS MATCH_REAL_WORLD USER_CONTROL CONSISTENCY
                    ERROR_PREVENTION RECOGNITION_OVER_RECALL FLEXIBILITY_EFFICIENCY
                    AESTHETIC_MINIMALISM ERROR_RECOVERY HELP_AND_DOCUMENTATION]
    assert_equal 10, heuristics.size
    heuristics.each do |id|
      assert_operator named.index(id), :<, first_node, id
      assert data.fetch("law_catalogue").fetch("entries").key?(id), id
    end
    assert_operator named.index("NNGROUP"), :<, named.index("SYSTEM_STATUS")
    assert_equal 13, named.grep(/^BAYMARD_/).size
    named.grep(/^BAYMARD_/).each { |id| assert_operator named.index(id), :<, first_node, id }
    assert_equal %w[DIP ISP LSP OCP SRP], named.grep(/\A(?:SRP|OCP|LSP|ISP|DIP)\z/).sort
    assert_equal 7, named.grep(/^STRUNK_WHITE_/).size
    assert_equal 10, named.grep(/^RAILS_DOCTRINE_/).size
  end

  def test_source_does_not_declare_duplicate_top_level_law_ids
    source = File.read(File.join(Master::ROOT, "data", "laws.yml"), encoding: "UTF-8")
    ids = source.lines.filter_map do |line|
      match = line.match(/\A([A-Z][A-Za-z0-9_]*):\s*\z/)
      match && match[1]
    end

    assert_equal ids.uniq.sort, ids.sort
  end
  private

  def retired_fields(data)
    policy = data.fetch("law_catalogue")
    rows = Master::FlatLawCatalogue.entries(data).to_h { |row| [row.fetch("id"), row] }
    rows["defaults"] = policy.fetch("defaults")
    policy.fetch("entries").each { |id, row| rows["entries.#{id}"] = row }
    forbidden = Master::FlatLawCatalogue::SCOPE_FIELDS + Master::FlatLawCatalogue::LEGACY_RANK_FIELDS
    rows.filter_map do |id, row|
      fields = row.keys & forbidden
      [id, fields] unless fields.empty?
    end.to_h
  end
end
