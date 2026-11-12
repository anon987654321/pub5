# frozen_string_literal: true

require "minitest/autorun"

class StructureRatchetTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  EXISTING_NESTED_ENGINE = "brgen/engines/marketplace/engines/takeaway"

  def test_no_new_nested_engine_roots_are_added
    nested = Dir.glob(File.join(ROOT, "brgen/engines/**/engines/*")).select { |path| File.directory?(path) }.map do |path|
      path.delete_prefix("#{ROOT}/")
    end.sort

    unexpected = nested - [EXISTING_NESTED_ENGINE]
    assert_empty unexpected,
                 "new nested engines need an explicit architecture decision: #{unexpected.join(", ")}"
  end
end
