# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/configuration_guard"

class TestConfigurationGuard < Minitest::Test
  Guard = Master::ConfigurationGuard

  def laws_path = File.join(Master::ROOT, "data", "laws.yml")
  def soul_path = File.join(Master::ROOT, "data", "soul.yml")
  def tokens_path = File.join(Master::ROOT, "data", "tokens.yml")

  def test_current_law_catalogue_satisfies_shared_invariants
    assert_nil Guard.validate(path: laws_path, content: File.read(laws_path, encoding: "UTF-8"))
  end

  def test_current_soul_allows_its_own_safe_edit_path
    assert_nil Guard.validate(path: soul_path, content: File.read(soul_path, encoding: "UTF-8"))
  end

  def test_current_token_catalogue_satisfies_shared_invariants
    assert_nil Guard.validate(path: tokens_path, content: File.read(tokens_path, encoding: "UTF-8"))
  end

  def test_token_catalogue_cannot_drop_a_required_section
    data = YAML.safe_load_file(tokens_path, aliases: true)
    data.fetch("tokens").delete("face_interface")

    reason = Guard.validate(path: tokens_path, content: YAML.dump(data))

    assert_match(/tokens\.yml is missing required token section\(s\): face_interface/, reason)
  end

  def test_token_catalogue_cannot_drift_a_shared_spacing_contract
    data = YAML.safe_load_file(tokens_path, aliases: true)
    data.fetch("tokens").fetch("pixel_perfection")["eight_px_rhythm"] = [0, 4, 8]

    reason = Guard.validate(path: tokens_path, content: YAML.dump(data))

    assert_match(/tokens\.scale\.space_px must match pixel_perfection\.eight_px_rhythm/, reason)
  end

  def test_face_default_mode_must_exist_in_face_mode_catalogue
    data = YAML.safe_load_file(tokens_path, aliases: true)
    data.fetch("tokens").fetch("face_interface").fetch("state")["default_mode"] = "missing_mode"

    reason = Guard.validate(path: tokens_path, content: YAML.dump(data))

    assert_match(/tokens\.face_interface\.state\.default_mode must be listed in modes/, reason)
  end

  def test_dynamic_tool_catalogue_uses_the_runtime_schema
    path = File.join(Master::ROOT, "data", "tools.dynamic.yml")

    assert_nil Guard.validate(path:, content: File.read(path, encoding: "UTF-8"))
  end

  def test_dynamic_tool_catalogue_cannot_hide_a_mapping_instead_of_a_list
    path = File.join(Master::ROOT, "data", "tools.dynamic.yml")
    content = YAML.dump("name" => "status_ping", "url" => "https://example.com")

    reason = Guard.validate(path:, content:)

    assert_match(/dynamic tool catalogue .* must be a YAML list/, reason)
  end

  def test_malformed_law_yaml_is_refused
    reason = Guard.validate(path: laws_path, content: "law_catalogue: [\n")
    assert_match(/configuration invariant failed/, reason)
  end

  def test_empty_law_source_is_refused
    reason = Guard.validate(path: laws_path, content: "law_catalogue: {}\n")
    assert_match(/laws.yml declares no flat laws/, reason)
  end

  def test_runtime_sections_are_required
    laws = YAML.safe_load_file(laws_path, aliases: true)
    # The Law rows and catalogue of the live file, minus its runtime sections.
    law_rows = laws.select { |_key, value| value.is_a?(Hash) && value["statement"] }
    reason = Guard.validate(
      path: laws_path,
      content: YAML.dump(law_rows.merge("law_catalogue" => laws.fetch("law_catalogue")))
    )
    assert_match(/required runtime configuration section/, reason)
  end

  def test_law_execution_policy_has_one_source
    laws = YAML.safe_load_file(laws_path, aliases: true)
    entries = laws.fetch("law_catalogue").fetch("entries")

    assert_operator entries.size, :>, 200
    assert laws.key?("veto_pattern_config")
    refute laws.key?("veto_patterns")
  end

  def test_catalogue_entry_cannot_drop_a_modality
    data = YAML.safe_load_file(laws_path, aliases: true)
    entry = data.fetch("law_catalogue").fetch("entries").values.first
    entry["modalities"] = %w[lexical semantic]
    reason = Guard.validate(path: laws_path, content: YAML.dump(data))
    assert_match(/cannot narrow the catalogue's modalities/, reason)
  end

  # The sacred-path list retired on 2026-11-09; a soul that brings it back is refused.
  def test_soul_cannot_reintroduce_the_retired_sacred_path_list
    data = YAML.safe_load_file(soul_path, aliases: true)
    data.fetch("absolute")["sacred_paths"] = %w[data/laws.yml]
    reason = Guard.validate(path: soul_path, content: YAML.dump(data))
    assert_match(/absolute has unknown field\(s\): sacred_paths/, reason)
  end

  def test_soul_rejects_an_empty_anti_simulation_word
    data = YAML.safe_load_file(soul_path, aliases: true)
    data.fetch("absolute").fetch("anti_simulation")["forbidden"] = [""]

    reason = Guard.validate(path: soul_path, content: YAML.dump(data))

    assert_match(/absolute\.anti_simulation\.forbidden/, reason)
  end

  def test_soul_keeps_anti_simulation_words_in_its_manifest
    data = YAML.safe_load_file(soul_path, aliases: true)

    assert_equal %w[will would could might], data.dig("absolute", "anti_simulation", "forbidden")
  end
end
