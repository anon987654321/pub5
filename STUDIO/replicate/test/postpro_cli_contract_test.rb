# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../../postpro/constitution"

class TestPostproCliContract < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

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

  def test_random_renders_never_retire_previous_takes
    constitution = source("postpro/constitution.rb")
    cli = source("postpro/lib/cli.rb")

    refute_includes constitution, "retire_previous_renders!"
    refute_includes constitution, "FileUtils.rm_f"
    refute_includes cli, "retire_previous_renders!"
    assert_includes constitution, "def verify_unused_output!"
    assert_includes constitution, "existing = existing_output(output)"
    assert_includes constitution, "raise ArgumentError, \"constitutional output already exists:"
    assert_includes constitution, "def available_output_path"
    assert_includes constitution, "verify_unused_output!(output)"
  end

  def test_random_take_identity_is_stable_and_bound_to_its_inputs
    take_class = Struct.new(:number, :look, :lane)
    take = take_class.new(2, :noir, :subtle)
    chain_a = [[:grain, { "intensity" => 0.2, "radius" => 1 }], [:halation, { "threshold" => 0.8 }]]
    chain_b = [[:grain, { "radius" => 1, "intensity" => 0.2 }], [:halation, { "threshold" => 0.8 }]]
    common = {
      input_sha256: "a" * 64,
      seed: 1234,
      take:,
      grade_version: "grade-v1",
    }

    identity = Postpro::Constitution.take_identity(**common, chain: chain_a)
    assert_match(/\A[a-f0-9]{64}\z/, identity)
    assert_equal identity, Postpro::Constitution.take_identity(**common, chain: chain_b)
    refute_equal identity, Postpro::Constitution.take_identity(**common.merge(seed: 1235), chain: chain_a)
    refute_equal identity, Postpro::Constitution.take_identity(**common.merge(input_sha256: "b" * 64), chain: chain_a)
    refute_equal identity, Postpro::Constitution.take_identity(**common.merge(grade_version: "grade-v2"), chain: chain_a)
    refute_equal identity, Postpro::Constitution.take_identity(**common.merge(take: take_class.new(3, :noir, :subtle)), chain: chain_a)
  end

  def test_random_chain_sidecars_include_the_content_bound_take_identity
    sidecars = source("postpro/lib/sidecars.rb")

    assert_includes sidecars, "Postpro::Constitution.take_identity("
    assert_includes sidecars, "data[:take_id] ="
  end

  def test_explicit_postpro_destinations_refuse_to_replace_existing_takes
    cli = source("postpro/lib/cli.rb")

    assert_includes cli, "verify_unused_output!(output_path)"
    assert_includes cli, "verify_unused_output!(comparison_path)"
    assert_includes cli, "verify_unused_output!(output)"
  end

  def test_explicit_lut_export_refuses_to_replace_an_existing_file
    vocab = source("postpro/lib/vocab_check.rb")

    assert_includes vocab, "verify_unused_output!(out)"
  end
end
