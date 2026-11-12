# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class RefinementsContractTest < Minitest::Test
  REPOSITORY_ROOT = File.expand_path("../..", __dir__)
  RAILS_ROOT = File.expand_path("..", __dir__)
  PATH = File.join(RAILS_ROOT, "refinements.yml")
  MAX_ROWS = 300

  def test_active_ledger_contains_only_open_items_with_resolvable_sources
    document = YAML.safe_load_file(PATH, aliases: false)
    assert_equal 1, document.fetch("schema")

    items = document.fetch("items")
    refute_empty items
    assert_operator items.length, :<=, MAX_ROWS, "active refinements exceed the row budget"

    ids = items.map { |item| item.fetch("id") }
    assert_equal ids.length, ids.uniq.length, "refinement IDs must be unique"

    items.each do |item|
      id = item.fetch("id")
      assert_equal "open", item.fetch("status"), "#{id} is not an open item"
      assert_match(/\A[a-z][a-z0-9_]*\z/, item.fetch("app"), "#{id} has an invalid app")

      path = item.fetch("path")
      assert_match(/\ARAILS\//, path, "#{id} path must be repository-relative")
      absolute = File.expand_path(path, REPOSITORY_ROOT)
      assert absolute.start_with?("#{REPOSITORY_ROOT}/"), "#{id} path escapes the repository"
      assert File.file?(absolute), "#{id} source does not exist: #{path}"
      refute_empty item.fetch("item").to_s.strip, "#{id} has no description"
    end
  end
end
