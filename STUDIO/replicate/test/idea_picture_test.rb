# frozen_string_literal: true

require "fileutils"
require_relative "minitest_helper"
require "open3"
require "tmpdir"
require_relative "../output_paths"
require_relative "../../lora/idea_picture"

# Synthetic subject authorization: real consent is tested separately.
Studio::Lora::Consent.define_singleton_method(:require!) { |**| { "valid" => true } }

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
    root = File.expand_path("../..", __dir__)
    canonical = File.join(root, "lora", "idea_picture.rb")
    duplicates = [File.join(root, "photograph", "idea_picture.rb"),
                  File.join(root, "generators", "idea_picture.rb"),
                  File.join(root, "lora", "photograph", "idea_picture.rb")]

    assert File.file?(canonical)
    duplicates.each do |duplicate|
      refute File.file?(duplicate), "keep the implementation in lora/ beside its siblings, not under #{duplicate}"
    end
  end
  def test_grade_returns_the_render_beside_the_still_not_the_still_itself
    Dir.mktmpdir do |dir|
      source = File.join(dir, "portrait source.jpg")
      File.write(source, "source")
      picture = Studio::Visual::IdeaPicture.new(directory: dir, subjects_root: dir)

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

  def test_render_still_retains_the_original_provider_output_after_grading
    Dir.mktmpdir do |dir|
      client = Object.new
      client.define_singleton_method(:download_url) { |_url, path| File.write(path, "provider-original") }
      picture = Studio::Visual::IdeaPicture.new(client:, directory: dir, subjects_root: dir)
      picture.define_singleton_method(:render_with_fallback) { |_words| "https://provider.example/still.jpg" }
      picture.define_singleton_method(:first_url) { |output| output }
      picture.define_singleton_method(:grade) do |path, seed: nil|
        graded = File.join(File.dirname(path), "postpro_#{File.basename(path, ".jpg")}_test_v1.jpg")
        File.write(graded, "graded")
        graded
      end

      graded = picture.send(:render_still, "portrait prompt", "johann_selfie_01")
      original = File.join(dir, "johann_selfie_01.jpg")

      assert_equal "provider-original", File.read(original)
      assert_equal "graded", File.read(graded)
      assert_equal 0o600, File.stat(original).mode & 0o777
      assert_equal 0o600, File.stat(graded).mode & 0o777
    end
  end

  def test_inference_profiles_are_rejected_for_generic_engines
    error = assert_raises(ArgumentError) do
      Studio::Visual::IdeaPicture.new(
        subject: "probe", engine: "black-forest-labs/flux-dev", inference_profile: "identity"
      )
    end
    assert_match(/only to the subject's pinned LoRA route/, error.message)
  end

  def test_lora_masters_default_to_png_when_provider_url_has_no_suffix
    Dir.mktmpdir do |dir|
      client = Object.new
      client.define_singleton_method(:download_url) { |_url, path| File.write(path, "provider-png") }
      picture = Studio::Visual::IdeaPicture.new(
        client:, directory: dir, subject: "probe", subjects_root: dir, lora_only: true
      )
      picture.define_singleton_method(:render_with_fallback) { |_words| "https://provider.example/download?id=123" }
      picture.define_singleton_method(:grade) do |path, seed: nil|
        graded = File.join(File.dirname(path), "postpro_#{File.basename(path, ".png")}_test_v1.png")
        File.write(graded, "graded-png")
        graded
      end

      graded = picture.send(:render_still, "portrait prompt", "probe_master")
      original = File.join(dir, "probe_master.png")
      assert_equal "provider-png", File.read(original)
      assert_equal "graded-png", File.read(graded)
      assert_equal 0o600, File.stat(original).mode & 0o777
    end
  end

  def test_any_existing_media_extension_blocks_before_a_paid_prediction
    Dir.mktmpdir do |dir|
      existing = File.join(dir, "probe_master.jpg")
      File.write(existing, "existing render")
      picture = Studio::Visual::IdeaPicture.new(directory: dir, subjects_root: dir)
      picture.define_singleton_method(:render_with_fallback) { |_words| flunk "must reject collision before provider access" }

      error = assert_raises(RuntimeError) do
        picture.send(:render_still, "portrait prompt", "probe_master")
      end
      assert_match(/refusing to replace an existing still/, error.message)
      assert_equal "existing render", File.read(existing)
    end
  end

  def test_grade_fails_instead_of_returning_an_ungraded_still
    Dir.mktmpdir do |dir|
      source = File.join(dir, "portrait.jpg")
      File.write(source, "source")
      picture = Studio::Visual::IdeaPicture.new(directory: dir, subjects_root: dir)

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

  def test_google_reference_input_uses_multi_image_schema_without_single_face_upload
    Dir.mktmpdir do |dir|
      subject_root = File.join(dir, "subjects")
      references = File.join(subject_root, "probe", "references")
      FileUtils.mkdir_p(references)
      File.write(File.join(references, "01.jpg"), "reference")
      uploads = []
      client = Object.new
      client.define_singleton_method(:upload_file) do |path, subject:|
        uploads << [File.basename(path), subject]
        "https://files.replicate.delivery/#{File.basename(path)}"
      end
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, subjects_root: subject_root
      )

      input = picture.send(:reference_input, "portrait", "google/nano-banana-2.1")
      assert_equal ["https://files.replicate.delivery/01.jpg"], input.fetch("image_input")
      assert_equal "2K", input.fetch("resolution")
      refute input.key?("subject_reference")
      assert_equal [["01.jpg", "probe"]], uploads
    end
  end

  # flux-2-flex counts megapixels and rejects a "2K" string; each engine gets
  # the value its own schema declares.
  def test_reference_input_sends_each_engine_its_own_sizing_vocabulary
    Dir.mktmpdir do |dir|
      subject_root = File.join(dir, "subjects")
      references = File.join(subject_root, "probe", "references")
      FileUtils.mkdir_p(references)
      File.write(File.join(references, "01.jpg"), "reference")
      client = Object.new
      client.define_singleton_method(:upload_file) { |_path, subject:| "https://files.replicate.delivery/#{subject}.jpg" }
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, subjects_root: subject_root
      )

      flex = picture.send(:reference_input, "portrait", "black-forest-labs/flux-2-flex")
      assert_equal "2 MP", flex.fetch("resolution")
      assert_equal ["https://files.replicate.delivery/probe.jpg"], flex.fetch("input_images")

      seedream = picture.send(:reference_input, "portrait", "bytedance/seedream-5-lite")
      assert_equal "2K", seedream.fetch("size")
    end
  end

  def test_reference_files_fall_back_to_published_sources
    Dir.mktmpdir do |dir|
      subject = File.join(dir, "probe")
      FileUtils.mkdir_p(File.join(subject, "sources", "additional"))
      File.write(File.join(subject, "sources", "additional", "01.jpg"), "recent")
      File.write(File.join(subject, "sources", "01.jpg"), "archive")

      files = Studio::Visual::IdeaPicture.reference_files(subject)

      assert_includes files, File.join(subject, "sources", "additional", "01.jpg")
      assert_includes files, File.join(subject, "sources", "01.jpg")
    end
  end

  def test_reference_engine_preflight_does_not_validate_the_subject_lora
    Dir.mktmpdir do |dir|
      subject_root = File.join(dir, "subjects")
      subject_dir = File.join(subject_root, "probe")
      FileUtils.mkdir_p(subject_dir, mode: 0o700)
      File.write(
        File.join(subject_dir, "subject.env"),
        "REPLICATE_MODEL=owner/model:version-123\nLIKELINESS_REVIEWED_VERSION=owner/model:version-123\n",
        mode: "w", perm: 0o600
      )
      seen = []
      client = Object.new
      client.define_singleton_method(:input_names) do |model|
        seen << model
        %w[prompt image_input aspect_ratio resolution output_format]
      end
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, subjects_root: subject_root,
        engine: "google/nano-banana-2.1"
      )

      assert_equal "google/nano-banana-2.1", picture.validate_model!
      assert_equal ["google/nano-banana-2.1"], seen
    end
  end

  def test_seedream_5_lite_uses_the_multi_image_reference_schema
    Dir.mktmpdir do |dir|
      subject_root = File.join(dir, "subjects")
      references = File.join(subject_root, "probe", "references")
      FileUtils.mkdir_p(references)
      File.write(File.join(references, "01.jpg"), "reference")
      client = Object.new
      client.define_singleton_method(:upload_file) do |path, subject:|
        "https://files.replicate.delivery/#{File.basename(path)}?s=#{subject}"
      end
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, subjects_root: subject_root
      )

      input = picture.send(:reference_input, "portrait", "bytedance/seedream-5-lite")

      assert_equal ["https://files.replicate.delivery/01.jpg?s=probe"], input.fetch("image_input")
      assert_equal "2K", input.fetch("size")
      assert_equal 1, input.fetch("max_images")
    end
  end

  def test_flux_kontext_max_uses_one_input_image
    Dir.mktmpdir do |dir|
      subject_root = File.join(dir, "subjects")
      references = File.join(subject_root, "probe", "references")
      FileUtils.mkdir_p(references)
      File.write(File.join(references, "01.jpg"), "reference")
      client = Object.new
      client.define_singleton_method(:upload_file) do |path, subject:|
        "https://files.replicate.delivery/#{File.basename(path)}?s=#{subject}"
      end
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, subjects_root: subject_root
      )

      input = picture.send(:reference_input, "portrait", "black-forest-labs/flux-kontext-max")

      assert_equal "https://files.replicate.delivery/01.jpg?s=probe", input.fetch("input_image")
      refute input.key?("image_input")
    end
  end

  def test_minimax_image_reference_uploads_only_one_subject_reference
    Dir.mktmpdir do |dir|
      subject_root = File.join(dir, "subjects")
      references = File.join(subject_root, "probe", "references")
      FileUtils.mkdir_p(references)
      %w[01.jpg 02.jpg 03.jpg].each { |name| File.write(File.join(references, name), "reference") }
      uploads = []
      client = Object.new
      client.define_singleton_method(:upload_file) do |path, subject:|
        uploads << File.basename(path)
        "https://files.replicate.delivery/#{File.basename(path)}"
      end
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, subjects_root: subject_root
      )

      input = picture.send(:reference_input, "portrait", "minimax/image-01")
      assert_equal "https://files.replicate.delivery/01.jpg", input.fetch("subject_reference")
      refute input.key?("image_input")
      assert_equal ["01.jpg"], uploads
    end
  end

  def test_subject_media_upload_requires_owner_only_single_linked_files
    Dir.mktmpdir do |dir|
      image = File.join(dir, "portrait.jpg")
      File.write(image, "private portrait", mode: "w", perm: 0o644)
      picture = Studio::Visual::IdeaPicture.new(subject: "probe", directory: dir)

      error = assert_raises(ArgumentError) { picture.send(:require_private_media_file!, image) }
      assert_match(/owner-only/, error.message)

      File.chmod(0o600, image)
      assert picture.send(:require_private_media_file!, image)
      linked = File.join(dir, "linked.jpg")
      File.link(image, linked)
      error = assert_raises(ArgumentError) { picture.send(:require_private_media_file!, image) }
      assert_match(/hard-linked/, error.message)
    end
  end

  def test_private_weights_manifest_requires_owner_only_directories_and_file
    Dir.mktmpdir do |dir|
      subject = File.join(dir, "probe")
      weights = File.join(subject, "weights")
      model_directory = File.join(weights, "probe")
      FileUtils.mkdir_p(model_directory, mode: 0o700)
      [subject, weights, model_directory].each { |path| File.chmod(0o700, path) }

      manifest = File.join(model_directory, "replicate_training.json")
      version = "owner/model:version-123"
      File.write(manifest, JSON.generate("version" => version), mode: "w", perm: 0o600)
      File.chmod(0o600, manifest)
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", directory: dir, subjects_root: dir
      )

      [subject, weights, model_directory].each do |path|
        File.chmod(0o755, path)
        error = assert_raises(RuntimeError) { picture.send(:still_model) }
        assert_match(/owner-only \(0700\)/, error.message)
        File.chmod(0o700, path)
      end

      File.chmod(0o644, manifest)
      error = assert_raises(RuntimeError) { picture.send(:still_model) }
      assert_match(/owner-only \(0600\)/, error.message)

      File.chmod(0o600, manifest)
      linked = File.join(model_directory, "linked.json")
      File.link(manifest, linked)
      error = assert_raises(RuntimeError) { picture.send(:still_model) }
      assert_match(/singly-linked/, error.message)
      File.unlink(linked)

      assert_equal version, picture.send(:still_model)
    end
  end

  def test_private_replicate_model_pin_requires_an_immutable_version_without_a_manifest
    Dir.mktmpdir do |dir|
      subject = File.join(dir, "ragnhild")
      FileUtils.mkdir_p(subject)
      subject_env_path = File.join(subject, "subject.env")
      version = "anon987654321/ragnhild-private:" + ("b" * 64)
      File.write(subject_env_path, <<~ENV)
        MODEL=ragnhild
        REPLICATE_MODEL=#{version}
        TRIGGER=ragnhild
      ENV
      File.chmod(0o600, subject_env_path)
      picture = Studio::Visual::IdeaPicture.new(
        subject: "ragnhild", directory: dir, subjects_root: dir,
        model_manifest: File.join(subject, "weights", "ragnhild", "replicate_training.json")
      )
      assert_equal version, picture.send(:still_model)
    end
  end

  def test_private_pinned_model_overrides_a_legacy_tracked_manifest
    Dir.mktmpdir do |dir|
      subject = File.join(dir, "ragnhild")
      FileUtils.mkdir_p(subject)
      old = "anon987654321/ragnhild-flux:" + ("a" * 64)
      current = "anon987654321/ragnhild-private:" + ("b" * 64)
      File.write(File.join(subject, "replicate_training.json"), JSON.generate("version" => old))
      env = File.join(subject, "subject.env")
      File.write(env, "MODEL=ragnhild\nREPLICATE_MODEL=#{current}\nTRIGGER=ragnhild\n", mode: "w", perm: 0o600)
      File.chmod(0o600, env)

      picture = Studio::Visual::IdeaPicture.new(subject: "ragnhild", directory: dir, subjects_root: dir)
      assert_equal current, picture.send(:still_model)
    end
  end

  def test_animate_refuses_missing_and_symlink_sources_before_provider_calls
    Dir.mktmpdir do |dir|
      client = Object.new
      client.define_singleton_method(:predict) { |*| flunk "provider must not be called" }
      picture = Studio::Visual::IdeaPicture.new(subject: "johann", client:, directory: dir, subjects_root: dir)

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

  def test_lora_only_requires_an_exact_human_reviewed_model_version
    Dir.mktmpdir do |dir|
      subjects = File.join(dir, "subjects")
      subject = File.join(subjects, "probe")
      FileUtils.mkdir_p(subject)
      manifest = File.join(subject, "replicate_training.json")
      version = "owner/model:version-123"
      File.write(manifest, JSON.generate("version" => version))
      env_path = File.join(subject, "subject.env")
      File.write(env_path, "MODEL=probe\nTRIGGER=probe\n")
      File.chmod(0o600, env_path)
      calls = []
      client = Object.new
      client.define_singleton_method(:input_names) do |model|
        calls << model
        %w[prompt model aspect_ratio num_outputs guidance_scale num_inference_steps output_format output_quality go_fast lora_scale]
      end
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, subjects_root: subjects,
        model_manifest: manifest, lora_only: true
      )

      error = assert_raises(RuntimeError) { picture.validate_model! }
      assert_match(/LIKELINESS_REVIEWED_VERSION/, error.message)
      assert_empty calls, "an unreviewed model must be blocked before the provider schema call"

      File.write(env_path, "MODEL=probe\nTRIGGER=probe\nLIKELINESS_REVIEWED_VERSION=#{version}\n")
      File.chmod(0o600, env_path)
      approved = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, subjects_root: subjects,
        model_manifest: manifest, lora_only: true
      )
      assert_equal version, approved.validate_model!
      assert_equal [version], calls
    end
  end

  def test_unreviewed_lora_is_allowed_only_inside_the_private_candidate_review_cache
    Dir.mktmpdir do |dir|
      subjects = File.join(dir, "subjects")
      subject = File.join(subjects, "probe")
      candidate = File.join(subject, ".cache", "likeness-review", "candidate-1")
      outside = File.join(subject, "out")
      FileUtils.mkdir_p(candidate, mode: 0o700)
      FileUtils.mkdir_p(outside, mode: 0o700)
      [subject, File.dirname(candidate), File.dirname(File.dirname(candidate)), candidate, outside].each do |path|
        File.chmod(0o700, path)
      end
      manifest = File.join(subject, "replicate_training.json")
      version = "owner/model:version-123"
      File.write(manifest, JSON.generate("version" => version))
      env_path = File.join(subject, "subject.env")
      File.write(env_path, "MODEL=probe\nTRIGGER=probe\n")
      File.chmod(0o600, env_path)
      client = Object.new
      client.define_singleton_method(:input_names) do |_model|
        %w[prompt model aspect_ratio num_outputs guidance_scale num_inference_steps output_format output_quality go_fast lora_scale]
      end

      allowed = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: candidate, subjects_root: subjects,
        model_manifest: manifest, lora_only: true, allow_unreviewed_likeness: true
      )
      assert_equal version, allowed.validate_model!

      blocked = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: outside, subjects_root: subjects,
        model_manifest: manifest, lora_only: true, allow_unreviewed_likeness: true
      )
      error = assert_raises(RuntimeError) { blocked.validate_model! }
      assert_match(/likeness is not approved/, error.message)
    end
  end

  def test_subject_lora_input_uses_the_named_profile_and_lossless_master_settings
    standard = Studio::ReplicateClient::TRAINING_STANDARDS.fetch("inference")
    profile = standard.fetch("profiles").fetch("balanced")
    picture = Studio::Visual::IdeaPicture.allocate
    picture.instance_variable_set(:@lora_only, true)
    picture.instance_variable_set(:@inference_profile, "balanced")
    picture.instance_variable_set(
      :@validated_still_inputs,
      %w[prompt model num_inference_steps guidance_scale aspect_ratio output_format lora_scale seed]
    )
    picture.define_singleton_method(:photographic) { |words| "johann_lora, #{words}" }

    input = picture.send(:lora_input, "portrait")
    assert_equal standard.fetch("model"), input.fetch(:model)
    assert_equal profile.fetch("num_inference_steps"), input.fetch(:num_inference_steps)
    assert_equal profile.fetch("guidance_scale"), input.fetch(:guidance_scale)
    assert_equal profile.fetch("lora_scale"), input.fetch(:lora_scale)
    assert_equal standard.fetch("aspect_ratio"), input.fetch(:aspect_ratio)
    assert_equal "png", input.fetch(:output_format)
    assert_equal standard.fetch("seed"), input.fetch(:seed)
    refute input.key?(:output_quality)
    refute input.key?(:go_fast)
  end

  def test_unsupported_inference_profile_is_rejected_before_provider_access
    error = assert_raises(ArgumentError) do
      Studio::Visual::IdeaPicture.new(subject: "probe", lora_only: true, inference_profile: "cinema-ultra")
    end
    assert_match(/unknown inference profile/, error.message)
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
      assert_match(/missing required FLUX inference inputs/, error.message)
      assert_match(/model/, error.message)
      assert_empty Dir.children(dir).grep(/\.jpg\z/)
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
      assert_empty Dir.children(dir).grep(/\.jpg\z/)
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
      assert_includes error.message, "owner/model:version in probe/subject.env"
    end
  end

  def test_schema_one_training_plan_supplies_subject_trigger_and_pinned_identity
    Dir.mktmpdir do |dir|
      subject = File.join(dir, "johann")
      FileUtils.mkdir_p(subject)
      version = "owner/johann-private:" + ("a" * 64)
      File.write(File.join(subject, "weights-placeholder.json"), "{}")
      File.write(File.join(subject, "replicate_training.json"), JSON.generate("version" => version))
      File.write(File.join(subject, "train.yaml"), <<~YAML)
        schema: 1
        subject: johann
        trigger_word: johann_lora
        dataset:
          path: dataset
          caption_ext: txt
        destination_env: REPLICATE_DESTINATION
        model_directory: johann
      YAML
      picture = Studio::Visual::IdeaPicture.new(
        subject: "johann", directory: dir, subjects_root: dir
      )

      assert_equal version, picture.send(:still_model)
      assert_match(/\Ajohann_lora,/, picture.send(:photographic, "window portrait"))
    end
  end

  def test_subject_env_must_be_owner_only_before_prompt_use
    Dir.mktmpdir do |dir|
      subject = File.join(dir, "probe")
      FileUtils.mkdir_p(subject)
      path = File.join(subject, "subject.env")
      File.write(path, "TRIGGER=probe\nDESCRIPTOR=private subject\n", mode: "w", perm: 0o644)

      # The owner-only gate fires at construction, before any prompt or
      # manifest read can touch the descriptor.
      error = assert_raises(RuntimeError) do
        Studio::Visual::IdeaPicture.new(subject: "probe", directory: dir, subjects_root: dir)
      end
      assert_match(/owner-only/, error.message)

      File.chmod(0o600, path)
      picture = Studio::Visual::IdeaPicture.new(subject: "probe", directory: dir, subjects_root: dir)
      assert_equal "private subject", picture.send(:subject_env).fetch("DESCRIPTOR")
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

  # Both H3 models take a first frame and a 4-15s duration. Lite also takes
  # an explicit resolution; Highspeed is fixed at 768P.
  def test_h3_film_engines_have_their_own_input_contracts
    assert_equal "minimax/h3-highspeed", Studio::Visual::IdeaPicture::FILM
    assert_equal %w[prompt first_frame_image duration resolution],
                 Studio::Visual::IdeaPicture::FILM_INPUT_KEYS.fetch("minimax/h3-lite")
    assert_equal %w[prompt first_frame_image duration],
                 Studio::Visual::IdeaPicture::FILM_INPUT_KEYS.fetch("minimax/h3-highspeed")
  end

  def test_h3_highspeed_film_input_uses_first_frame_without_resolution
    Dir.mktmpdir do |dir|
      still = File.join(dir, "still.jpg")
      File.write(still, "image")
      client = Object.new
      client.define_singleton_method(:upload_file) { |path, subject:| "https://example.test/#{File.basename(path)}?s=#{subject}" }
      picture = Studio::Visual::IdeaPicture.new(subject: "probe", client:, directory: dir)

      input = picture.send(:film_input, "slow turn", still, 2)
      assert_equal "https://example.test/still.jpg?s=probe", input[:first_frame_image]
      assert_equal 4, input[:duration]
      refute input.key?(:resolution), "Highspeed is fixed at 768P"
      refute input.key?(:image), "H3 Highspeed takes first_frame_image"
    end
  end

  def test_film_input_uses_the_first_frame_and_clamps_duration_to_h3_bounds
    Dir.mktmpdir do |dir|
      still = File.join(dir, "still.jpg")
      File.write(still, "image")
      client = Object.new
      client.define_singleton_method(:upload_file) { |path, subject:| "https://example.test/#{File.basename(path)}?s=#{subject}" }
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, film_engine: "minimax/h3-lite"
      )

      input = picture.send(:film_input, "slow turn", still, 2)
      assert_equal "https://example.test/still.jpg?s=probe", input[:first_frame_image]
      assert_equal 4, input[:duration], "H3 Lite's floor is 4s; 2s would be rejected"
      refute input.key?(:image), "H3 Lite takes first_frame_image, not image"
      assert_equal "480P", input[:resolution]

      higher_resolution = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, film_engine: "minimax/h3-lite",
        film_resolution: "768P"
      )
      assert_equal "768P", higher_resolution.send(:film_input, "turn", still, 8)[:resolution]
      assert_equal 15, picture.send(:film_input, "turn", still, 30)[:duration]
      assert_equal 8, picture.send(:film_input, "turn", still, 8)[:duration]
    end
  end

  def test_h3_lite_rejects_invalid_resolution_before_upload
    Dir.mktmpdir do |dir|
      still = File.join(dir, "still.jpg")
      File.write(still, "image")
      client = Object.new
      client.define_singleton_method(:upload_file) { |*| flunk "invalid resolution must fail before upload" }
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, film_engine: "minimax/h3-lite",
        film_resolution: "4K"
      )

      error = assert_raises(ArgumentError) { picture.send(:film_input, "slow turn", still, 5) }
      assert_match(/resolution must be 480P or 768P/, error.message)
    end
  end

  # Kling v3 Omni is the second selectable film engine. It takes start_image and
  # a 3-15s duration, and its native audio stays off because STUDIO lays the
  # dilla bed under the cut itself.
  def test_kling_v3_omni_is_selectable_and_takes_start_image
    Dir.mktmpdir do |dir|
      still = File.join(dir, "still.jpg")
      File.write(still, "image")
      client = Object.new
      client.define_singleton_method(:upload_file) { |path, subject:| "https://example.test/#{File.basename(path)}?s=#{subject}" }
      picture = Studio::Visual::IdeaPicture.new(
        subject: "probe", client:, directory: dir, film_engine: "kwaivgi/kling-v3-omni-video"
      )

      input = picture.send(:film_input, "slow turn", still, 2)
      assert_equal "https://example.test/still.jpg?s=probe", input[:start_image]
      assert_equal 3, input[:duration], "Kling's floor is 3s"
      assert_equal false, input[:generate_audio], "STUDIO scores the cut; the provider track would fight the bed"
      refute input.key?(:image), "Kling takes start_image, not image"
      refute input.key?(:first_frame_image)

      assert_equal 15, picture.send(:film_input, "turn", still, 30)[:duration]
      assert_equal %w[prompt start_image duration mode generate_audio],
                   Studio::Visual::IdeaPicture::FILM_INPUT_KEYS.fetch("kwaivgi/kling-v3-omni-video")
    end
  end

  def test_film_render_writes_private_receipt_with_hashes_and_estimate
    Dir.mktmpdir do |dir|
      still = File.join(dir, "source.jpg")
      File.binwrite(still, "approved still")
      provider_receipt = {
        "schema" => "studio.replicate.prediction.v1",
        "model" => "minimax/h3-highspeed",
        "version" => "a" * 64,
        "prediction_id" => "prediction-test",
        "status" => "succeeded",
        "estimated_cost_usd" => 0.30,
        "actual_cost_usd" => nil,
        "actual_cost_status" => "NOT_REPORTED_BY_PREDICTION_API"
      }
      client = Object.new
      client.define_singleton_method(:upload_file) do |_path, subject:|
        "https://files.replicate.delivery/source-#{subject}.jpg"
      end
      client.define_singleton_method(:predict_with_receipt) do |model, input, timeout:|
        raise "unexpected model" unless model == "minimax/h3-highspeed"
        raise "unexpected timeout" unless timeout == 600
        raise "missing first frame" unless input.key?(:first_frame_image)
        { "output" => "https://files.replicate.delivery/test.mp4", "receipt" => provider_receipt }
      end
      client.define_singleton_method(:download_url) do |url, path|
        raise "unexpected download URL" unless url == "https://files.replicate.delivery/test.mp4"
        File.binwrite(path, "video bytes")
        path
      end
      picture = Studio::Visual::IdeaPicture.new(subject: "probe", client:, directory: dir)
      video = picture.send(:render_film, "slow camera move", still, "probe_film_test", 5)
      receipt_path = "#{video}.json"
      receipt = JSON.parse(File.read(receipt_path))

      assert_equal "studio.film_render.v1", receipt.fetch("schema")
      assert_equal "probe", receipt.fetch("subject")
      assert_equal "minimax/h3-highspeed", receipt.fetch("model")
      assert_equal 5, receipt.fetch("requested_duration_seconds")
      assert_equal Digest::SHA256.file(still).hexdigest, receipt.fetch("source_still_sha256")
      assert_equal Digest::SHA256.file(video).hexdigest, receipt.fetch("output_video_sha256")
      assert_equal "prediction-test", receipt.dig("provider_prediction", "prediction_id")
      assert_nil receipt.dig("provider_prediction", "actual_cost_usd")
      assert_equal "NOT_REPORTED_BY_PREDICTION_API",
                   receipt.dig("provider_prediction", "actual_cost_status")
      assert_equal "NOT_REVIEWED", receipt.dig("human_review", "visual")
      assert_equal "NOT_REVIEWED", receipt.dig("human_review", "likeness")
      assert_equal 0o600, File.stat(video).mode & 0o777
      assert_equal 0o600, File.stat(receipt_path).mode & 0o777
    end
  end

  def test_the_film_engine_defaults_to_h3_highspeed_when_not_selected
    picture = Studio::Visual::IdeaPicture.new(subject: "probe", directory: Dir.pwd)
    assert_equal "minimax/h3-highspeed", picture.film_engine
  end

  def test_the_catalogue_rejects_an_unknown_film_engine
    models = Studio::ReplicateClient::Models
    spec = models.film_engine("kwaivgi/kling-v3-omni-video")
    assert_includes spec.fetch("inputs"), "start_image"
    assert_equal "minimax/h3-highspeed", Studio::Visual::IdeaPicture::FILM
    assert_includes models.film_engines.keys, Studio::Visual::IdeaPicture::FILM

    error = assert_raises(ArgumentError) { models.film_engine("bogus/nope") }
    assert_match(/unknown film engine/, error.message)
  end

  def test_minimax_video_prices_include_promotion_and_reference_video_billing
    models = Studio::ReplicateClient::Models
    today = Date.new(2026, 11, 17)
    lite_480 = { "duration" => 10, "resolution" => "480P" }
    lite_768 = { "duration" => 10, "resolution" => "768P" }
    highspeed = { "duration" => 10 }

    assert_in_delta 0.125, models.video_cost_usd("minimax/h3-lite", lite_480, today:), 0.001
    assert_in_delta 0.20, models.video_cost_usd("minimax/h3-lite", lite_768, today:), 0.001
    assert_in_delta 0.30, models.video_cost_usd("minimax/h3-highspeed", highspeed, today:), 0.001
    assert_in_delta 0.60, models.video_cost_usd("minimax/h3-highspeed", highspeed, today: Date.new(2027, 1, 1)), 0.001

    references = highspeed.merge("reference_video_urls" => %w[https://example.test/a.mp4 https://example.test/b.mp4])
    assert_in_delta 0.75, models.video_cost_usd("minimax/h3-highspeed", references, today:), 0.001
    assert_raises(ArgumentError) do
      models.video_cost_usd("minimax/h3-highspeed",
                           highspeed.merge("reference_video_urls" => %w[a b c d]), today:)
    end
  end

  def test_minimax_budget_refuses_a_call_that_exceeds_the_run_ceiling
    models = Studio::ReplicateClient::Models
    previous_budget = ENV["STUDIO_VIDEO_BUDGET_USD"]
    previous_cap = ENV["STUDIO_VIDEO_CALL_CAP_USD"]
    ENV["STUDIO_VIDEO_BUDGET_USD"] = "0.25"
    ENV["STUDIO_VIDEO_CALL_CAP_USD"] = "1.00"
    models.reset_video_budget!

    error = assert_raises(Studio::ReplicateClient::Models::BudgetExceeded) do
      models.reserve_video_spend!("minimax/h3-highspeed", { "duration" => 10 }, today: Date.new(2026, 11, 17))
    end
    assert_match(/remaining run budget/, error.message)
    assert_in_delta 0.0, models.video_budget_spent, 0.001
  ensure
    previous_budget ? ENV["STUDIO_VIDEO_BUDGET_USD"] = previous_budget : ENV.delete("STUDIO_VIDEO_BUDGET_USD")
    previous_cap ? ENV["STUDIO_VIDEO_CALL_CAP_USD"] = previous_cap : ENV.delete("STUDIO_VIDEO_CALL_CAP_USD")
    Studio::ReplicateClient::Models.reset_video_budget!
  end

  def test_minimax_budget_refuses_a_call_over_the_per_call_ceiling
    models = Studio::ReplicateClient::Models
    previous_budget = ENV["STUDIO_VIDEO_BUDGET_USD"]
    previous_cap = ENV["STUDIO_VIDEO_CALL_CAP_USD"]
    ENV["STUDIO_VIDEO_BUDGET_USD"] = "5.00"
    ENV["STUDIO_VIDEO_CALL_CAP_USD"] = "0.20"
    models.reset_video_budget!

    error = assert_raises(Studio::ReplicateClient::Models::BudgetExceeded) do
      models.reserve_video_spend!("minimax/h3-highspeed", { "duration" => 10 }, today: Date.new(2026, 11, 17))
    end
    assert_match(/per-call cap/, error.message)
    assert_in_delta 0.0, models.video_budget_spent, 0.001
  ensure
    previous_budget ? ENV["STUDIO_VIDEO_BUDGET_USD"] = previous_budget : ENV.delete("STUDIO_VIDEO_BUDGET_USD")
    previous_cap ? ENV["STUDIO_VIDEO_CALL_CAP_USD"] = previous_cap : ENV.delete("STUDIO_VIDEO_CALL_CAP_USD")
    Studio::ReplicateClient::Models.reset_video_budget!
  end

  def test_add_soundtrack_muxes_real_audio_and_keeps_the_silent_original
    skip "ffmpeg is not on PATH" unless system("ffmpeg", "-version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      clip = File.join(dir, "film.mp4")
      wav = File.join(dir, "dilla.wav")
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "color=c=black:s=64x64:d=2", "-c:v", "libx264", "-pix_fmt", "yuv420p", clip)
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "sine=frequency=200:duration=4", wav)

      picture = Studio::Visual::IdeaPicture.new(subject: "probe", directory: dir)
      scored = picture.add_soundtrack(clip, wav)

      assert_equal File.join(dir, "film_audio.mp4"), scored
      assert File.file?(clip), "the silent provider clip is left in place"
      probe, = Open3.capture2e("ffprobe", "-v", "error", "-show_entries",
                               "stream=codec_type", "-of", "csv=p=0", scored)
      assert_includes probe, "video"
      assert_includes probe, "audio"

      error = assert_raises(RuntimeError) { picture.add_soundtrack(clip, wav) }
      assert_match(/refusing to replace/, error.message)
    end
  end
end
