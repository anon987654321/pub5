# frozen_string_literal: true

require_relative "minitest_helper"

class TestPostproCliContract < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source(path)
    File.read(File.join(ROOT, path))
  end

  def test_unported_style_registry_has_no_conditional_loader_or_dead_resolver
    entry = source("postpro/postpro.rb")
    launch = source("postpro/lib/launch.rb")

    refute_includes entry, "../style_registry"
    refute_includes launch, "Studio::StyleRegistry.resolve"
    refute_includes launch, "Studio::StyleRegistry::InvalidStyle"
    assert_includes launch, 'return unless argv_flag("--style-contract")'
    assert_includes launch, "the registry is not part of this build"
  end

  def test_unported_source_map_has_no_conditional_loader_or_dead_renderer
    entry = source("postpro/postpro.rb")
    vocab = source("postpro/lib/vocab_check.rb")

    refute_includes entry, "../source_map"
    refute_includes vocab, "Studio::SourceMap.render"
    assert_includes vocab, 'elsif ARGV.include?("--map")'
    assert_includes vocab, "source-map support is not part of this build"
  end

  def test_help_does_not_claim_unavailable_features_work
    usage = source("postpro/postpro.rb")

    assert_includes usage, "--style-contract NAME            unavailable:"
    assert_includes usage, "--map                             unavailable:"
    refute_includes usage, "validate and record an image style contract"
  end
end
