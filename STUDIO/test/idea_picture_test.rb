# frozen_string_literal: true

require "fileutils"
require_relative "minitest_helper"
require "open3"
require "tmpdir"
require_relative "../output_paths"
require_relative "../photograph/idea_picture"

class TestStudioOutputPaths < Minitest::Test
  def test_relative_xdg_data_home_uses_an_absolute_fallback_from_any_directory
    with_environment("POSTPRO_OUTPUT_DIR", nil) do
      with_environment("XDG_DATA_HOME", "relative/data") do
        Dir.mktmpdir do |working_directory|
          Dir.chdir(working_directory) do
            path = Studio::OutputPaths.render_directory
            expected = File.expand_path("~/Downloads")
            assert_equal expected, path
            assert path.start_with?(File::SEPARATOR)
          end
        end
      end
    end
  end

  def test_explicit_output_directory_is_respected
    Dir.mktmpdir do |dir|
      with_environment("POSTPRO_OUTPUT_DIR", File.join(dir, "media")) do
        assert_equal File.join(File.realpath(dir), "media"), Studio::OutputPaths.render_directory
      end
    end
  end

  def test_xdg_data_home_inside_the_checkout_falls_back_outside_it
    with_environment("POSTPRO_OUTPUT_DIR", nil) do
      repo_root = File.expand_path("..", Studio::Visual::IdeaPicture::ROOT)
      with_environment("XDG_DATA_HOME", File.join(repo_root, "temporary-output")) do
        path = Studio::OutputPaths.render_directory
        expected = File.expand_path("~/Downloads")

        assert_equal expected, path
        refute path.start_with?("#{repo_root}#{File::SEPARATOR}")
      end
    end
  end

  def test_xdg_symlink_into_the_checkout_falls_back_outside_it
    with_environment("POSTPRO_OUTPUT_DIR", nil) do
      Dir.mktmpdir do |dir|
        repo_root = File.expand_path("..", Studio::Visual::IdeaPicture::ROOT)
        link = File.join(dir, "repository")
        File.symlink(repo_root, link)

        with_environment("XDG_DATA_HOME", File.join(link, "temporary-output")) do
          path = Studio::OutputPaths.render_directory
          expected = File.expand_path("~/Downloads")

          assert_equal expected, path
          assert Studio::OutputPaths.inside_repository?(File.join(link, "temporary-output"))
        end
      end
    end
  end

  def test_fallback_refuses_a_documents_path_that_resolves_into_the_checkout
    link_parent = Dir.mktmpdir
    link = File.join(link_parent, "documents")
    File.symlink(Studio::OutputPaths::REPOSITORY_ROOT, link)

    error = assert_raises(ArgumentError) do
      Studio::OutputPaths.fallback_data_home(link)
    end
    assert_match(/resolves inside the checkout/, error.message)
  ensure
    FileUtils.remove_entry(link_parent) if link_parent && File.directory?(link_parent)
  end

  def test_render_and_reference_paths_share_the_valid_xdg_data_home
    with_environment("POSTPRO_OUTPUT_DIR", nil) do
      with_environment("DILLA_OUTPUT_DIR", nil) do
        Dir.mktmpdir do |dir|
          # realpath: on macOS the tmpdir is a /var symlink to /private/var, and the paths resolve it.
          xdg_home = File.join(File.realpath(dir), "xdg")
          with_environment("XDG_DATA_HOME", xdg_home) do
            assert_equal xdg_home, Studio::OutputPaths.render_directory
            assert_equal xdg_home, Studio::OutputPaths.dilla_render_directory
            assert_equal File.join(xdg_home, "dilla-references"),
                         Studio::OutputPaths.reference_root
          end
        end
      end
    end
  end

  def test_render_overrides_do_not_change_the_reference_profile_root
    Dir.mktmpdir do |dir|
      base = File.realpath(dir) # macOS's /var is /private/var
      dilla = File.join(base, "dilla")
      postpro = File.join(base, "postpro")

      with_environment("DILLA_OUTPUT_DIR", dilla) do
        with_environment("POSTPRO_OUTPUT_DIR", postpro) do
          assert_equal dilla, Studio::OutputPaths.dilla_render_directory
          assert_equal postpro, Studio::OutputPaths.render_directory
          assert_equal File.join(Studio::OutputPaths.data_home, "dilla-references"),
                       Studio::OutputPaths.reference_root
        end
      end
    end
  end

  private

  def with_environment(name, value)
    previous = ENV[name]
    value.nil? ? ENV.delete(name) : ENV[name] = value
    yield
  ensure
    previous.nil? ? ENV.delete(name) : ENV[name] = previous
  end
end

class TestIdeaPictureOutput < Minitest::Test
  def test_idea_picture_has_one_canonical_implementation
    root = File.expand_path("..", __dir__)
    canonical = File.join(root, "photograph", "idea_picture.rb")
    duplicate = File.join(root, "generators", "idea_picture.rb")

    assert File.file?(canonical)
    refute File.file?(duplicate), "keep the implementation beside its photograph entrypoint"
  end
  def test_grade_returns_the_render_beside_the_still_not_the_still_itself
    Dir.mktmpdir do |dir|
      source = File.join(dir, "portrait source.jpg")
      File.write(source, "source")
      picture = Studio::Visual::IdeaPicture.new(directory: dir)

      graded = Dir.mktmpdir do |working_directory|
        Dir.chdir(working_directory) do
          Studio::Subprocess.stub(:capture3, postpro_writing_beside(dir)) { picture.send(:grade, source) }
        end
      end

      assert_equal File.join(dir, "postpro_portrait_source_test_v1.jpg"), graded
      refute_equal source, graded
      assert_equal "graded", File.read(graded)
    end
  end

  # A stand-in for the postpro subprocess: it checks how it was called and
  # writes its grade beside the still, the way postpro does.
  def postpro_writing_beside(dir)
    status = successful_status
    lambda do |env, *args, timeout:|
      script = File.join(Studio::Visual::IdeaPicture::ROOT, "postpro", "postpro.rb")
      assert_equal [600, script], [timeout, args.fetch(1)]

      refute env.key?("POSTPRO_OUTPUT_DIR"), "the grade lands beside the still, unredirected"
      File.write(File.join(dir, "postpro_portrait_source_test_v1.jpg"), "graded")
      ["postpro0: ok write", "", status]
    end
  end

  def test_grade_fails_instead_of_returning_an_ungraded_still
    Dir.mktmpdir do |dir|
      source = File.join(dir, "portrait.jpg")
      File.write(source, "source")
      picture = Studio::Visual::IdeaPicture.new(directory: dir)

      Studio::Subprocess.stub(:capture3, ->(_env, *_args, timeout:) { ["postpro0: ok", "", successful_status] }) do
        error = assert_raises(RuntimeError) { picture.send(:grade, source) }
        assert_match(/produced no graded still/, error.message)
      end
    end
  end

  private

  def successful_status
    Object.new.tap { |status| status.define_singleton_method(:success?) { true } }
  end

  public


  def test_private_replicate_model_name_is_a_supported_fallback_without_a_manifest
    Dir.mktmpdir do |dir|
      subject = File.join(dir, "ragnhild")
      FileUtils.mkdir_p(subject)
      File.write(File.join(subject, "subject.env"), <<~ENV)
        MODEL=ragnhild
        REPLICATE_MODEL=anon987654321/ragnhild-flux
        TRIGGER=ragnhild
      ENV
      picture = Studio::Visual::IdeaPicture.new(
        subject: "ragnhild", directory: dir,
        model_manifest: File.join(subject, "weights", "ragnhild", "replicate_training.json")
      )
      assert_equal "anon987654321/ragnhild-flux", picture.send(:still_model)
    end
  end

  def test_animate_refuses_missing_and_symlink_sources_before_provider_calls
    Dir.mktmpdir do |dir|
      client = Object.new
      client.define_singleton_method(:predict) { |*| flunk "provider must not be called" }
      picture = Studio::Visual::IdeaPicture.new(subject: "johann", client:, directory: dir)

      error = assert_raises(ArgumentError) { picture.animate(File.join(dir, "missing.jpg"), "motion") }
      assert_match(/source still is missing/, error.message)

      target = File.join(dir, "real.jpg")
      File.write(target, "image")
      link = File.join(dir, "link.jpg")
      File.symlink(target, link)
      error = assert_raises(ArgumentError) { picture.animate(link, "motion") }
      assert_match(/source still is missing/, error.message)
    end
  end


  def test_validate_model_checks_that_the_private_provider_model_is_reachable
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "replicate_training.json")
      File.write(manifest, JSON.generate("version" => "owner/model:version-123"))
      client = Object.new
      seen = nil
      client.define_singleton_method(:input_names) do |model|
        seen = model
        %w[prompt model aspect_ratio num_outputs guidance_scale num_inference_steps output_format output_quality go_fast lora_scale]
      end
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, model_manifest: manifest
      )

      assert_equal "owner/model:version-123", picture.validate_model!
      assert_equal "owner/model:version-123", seen
    end
  end

  def test_still_schema_preflight_catches_every_field_before_prediction
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "replicate_training.json")
      File.write(manifest, JSON.generate("version" => "owner/model:version-123"))
      client = Object.new
      client.define_singleton_method(:input_names) { |_model| %w[prompt] }
      client.define_singleton_method(:predict) { |*| flunk "prediction must not start with an incomplete input schema" }
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, model_manifest: manifest
      )

      error = assert_raises(RuntimeError) { picture.write("portrait", film: false) }
      assert_match(/missing inputs used by the still renderer/, error.message)
      assert_match(/aspect_ratio/, error.message)
      assert_empty Dir.children(dir).grep(/\\.jpg\z/)
    end
  end

  def test_film_schema_preflight_happens_before_still_generation_or_upload
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "replicate_training.json")
      File.write(manifest, JSON.generate("version" => "owner/model:version-123"))
      still_fields = %w[prompt model aspect_ratio num_outputs guidance_scale num_inference_steps output_format output_quality go_fast lora_scale]
      client = Object.new
      client.define_singleton_method(:input_names) do |model|
        model == Studio::Visual::IdeaPicture::FILM ? %w[prompt image] : still_fields
      end
      client.define_singleton_method(:predict) { |*| flunk "still prediction must not start before film schema review" }
      client.define_singleton_method(:upload_file) { |*| flunk "still upload must not start before film schema review" }
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, model_manifest: manifest
      )

      error = assert_raises(RuntimeError) { picture.write("portrait", film: true) }
      assert_match(/film model/, error.message)
      assert_match(/duration/, error.message)
      assert_empty Dir.children(dir).grep(/\\.jpg\z/)
    end
  end

  def test_subject_manifest_is_configurable_and_missing_manifest_is_actionable
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "replicate_training.json")
      File.write(manifest, JSON.generate("version" => "owner/model:version-123"))
      picture = Studio::Visual::IdeaPicture.new(
        directory: dir, subject: "probe", model_manifest: manifest
      )
      assert_equal "owner/model:version-123", picture.send(:still_model)

      missing = File.join(dir, "missing", "replicate_training.json")
      blocked = Studio::Visual::IdeaPicture.new(
        directory: dir, subject: "probe", model_manifest: missing
      )
      error = assert_raises(RuntimeError) { blocked.send(:still_model) }
      assert_includes error.message, missing
      assert_includes error.message, "approved training run"
    end
  end

  def test_manifest_rejects_versions_that_are_not_provider_model_version_ids
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "replicate_training.json")
      File.write(manifest, JSON.generate("version" => "not-a-model-version"))
      picture = Studio::Visual::IdeaPicture.new(
        directory: dir, subject: "probe", model_manifest: manifest
      )

      error = assert_raises(RuntimeError) { picture.send(:still_model) }
      assert_includes error.message, "owner/model:version"
    end
  end

  def test_subject_name_cannot_escape_the_lora_directory
    error = assert_raises(ArgumentError) do
      Studio::Visual::IdeaPicture.new(subject: "../elsewhere")
    end
    assert_match(/simple directory name/, error.message)
  end
end
