# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "minitest_helper"
require_relative "../../lora/selfie_series"

# Synthetic subject authorization: real consent is tested separately.
Studio::Lora::Consent.define_singleton_method(:require!) { |**| { "valid" => true } }

class TestSelfieSeries < Minitest::Test
  # A stand-in for the Replicate predict/download round trip, in the shape
  # idea_picture_test.rb already established for graded stills.
  class FakeClient
    attr_reader :predictions

    def initialize(fail_download_at: nil)
      @predictions = []
      @downloads = []
      @attempts = 0
      @fail_download_at = fail_download_at
    end

    def predict(model_id, input, timeout: nil)
      @predictions << [model_id, input]
      { "output" => "https://replicate.delivery/selfie.jpg" }
    end

    def input_names(_model_id)
      %w[prompt model aspect_ratio num_outputs guidance_scale num_inference_steps output_format output_quality go_fast lora_scale]
    end

    def download_url(url, path)
      @attempts += 1
      raise IOError, "network lost" if @fail_download_at && @attempts == @fail_download_at

      @downloads << path
      File.write(path, "render")
      path
    end
  end

  # A reference-capable engine must be preflighted against its own schema, not
  # the subject LoRA's. The fake exposes the current Google reference inputs and
  # records the uploaded source photographs.
  class ReferenceClient < FakeClient
    attr_reader :uploads

    def initialize
      super
      @uploads = []
    end

    def input_names(_model_id)
      %w[prompt image_input aspect_ratio resolution output_format]
    end

    def upload_file(path, subject:)
      @uploads << [path, subject]
      "https://files.replicate.delivery/#{File.basename(path)}"
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @client = FakeClient.new
    @graded_paths = []
    graded_paths = @graded_paths
    Studio::Visual::IdeaPicture.class_eval do
      alias_method :grade_without_stub, :grade
      define_method(:grade) do |path, **|
        stem = File.basename(path, File.extname(path))
        graded = File.join(File.dirname(path), "postpro_#{stem}_portrait_v1.jpg")
        raise "refusing to replace a graded fixture" if File.exist?(graded) || File.symlink?(graded)

        File.write(graded, "postpro graded image", mode: "w", perm: 0o600)
        File.chmod(0o600, graded)
        graded_paths << graded
        graded
      end
      alias_method :still_model_without_stub, :still_model
      define_method(:still_model) { "owner/model:version-123" }
      alias_method :subject_env_without_stub, :subject_env
      define_method(:subject_env) { { "LIKELINESS_REVIEWED_VERSION" => "owner/model:version-123" } }
    end
  end

  def teardown
    Studio::Visual::IdeaPicture.class_eval do
      remove_method(:grade)
      alias_method :grade, :grade_without_stub
      remove_method(:grade_without_stub)
      remove_method(:still_model)
      alias_method :still_model, :still_model_without_stub
      remove_method(:still_model_without_stub)
      remove_method(:subject_env)
      alias_method :subject_env, :subject_env_without_stub
      remove_method(:subject_env_without_stub)
    end
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  # The graded pass shells out to postpro and the manifest lookup needs a
  # subject with an approved training — both are no-op'd in setup here the way
  # idea_picture_test.rb stubs the same seams, and every write stays in tmpdir.
  def series(fail_download_at: nil, inference_profile: nil, client: nil, subjects_root: nil)
    Studio::Visual::SelfieSeries.new(
      subject: "probe",
      client: client || (fail_download_at ? FakeClient.new(fail_download_at:) : @client),
      directory: File.join(@dir, "stills"),
      subjects_root:,
      ledger_path: File.join(@dir, "ledger.jsonl"),
      inference_profile:,
    )
  end

  # --heavy opts a series back into the legacy random pass, so every frame is
  # developed without a recipe preset; the default keeps the named grade.
  def test_series_sends_recipe_presets_unless_heavy_is_requested
    Dir.mktmpdir do |dir|
      subject_root = File.join(dir, "subjects")
      FileUtils.mkdir_p(File.join(subject_root, "probe", "references"))
      File.write(File.join(subject_root, "probe", "references", "01.jpg"), "reference")

      captured = []
      recorder = Object.new
      recorder.define_singleton_method(:inference_profile) { nil }
      recorder.define_singleton_method(:engine) { "probe/engine" }
      recorder.define_singleton_method(:validate_model!) { {} }
      recorder.define_singleton_method(:write) do |_words, **kwargs|
        captured << kwargs[:preset]
        path = File.join(dir, "still_#{captured.length}.png")
        File.write(path, "render")
        { "still" => path }
      end

      [false, true].each do |heavy|
        series = Studio::Visual::SelfieSeries.new(
          subject: "probe", directory: dir, subjects_root: subject_root,
          ledger_path: File.join(dir, "ledger.jsonl"), heavy:
        )
        series.instance_variable_set(:@series, recorder)
        series.run(count: 1)
      end

      assert_equal 2, captured.length
      refute_nil captured.first
      assert_nil captured.last
    end
  end

  def test_a_series_renders_stills_with_subject_prefixed_filenames_in_the_lora_root
    rendered = run_series(series, count: 3)

    assert_equal 3, rendered.size
    rendered.each do |path|
      assert File.file?(path)
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
    assert File.file?(rendered.first)
    assert rendered.all? { |path| File.basename(path).include?("probe_selfie_") }
  end

  def test_every_rendered_selfie_receives_its_own_postpro_grade
    rendered = run_series(series, count: 4)

    assert_equal 4, rendered.length
    assert_equal 4, @graded_paths.length
    assert_equal rendered.sort, @graded_paths.sort
    assert rendered.all? { |path| File.basename(path).start_with?("postpro_probe_selfie_") }
    rendered.each { |path| assert_equal "postpro graded image", File.read(path) }
  end

  def test_selected_profile_reaches_inference_and_is_recorded_in_the_series_ledger
    run_series(series(inference_profile: "identity"), count: 1)

    settings = Studio::ReplicateClient::TRAINING_STANDARDS.fetch("inference").fetch("profiles").fetch("identity")
    input = @client.predictions.fetch(0).fetch(1)
    assert_equal settings.fetch("guidance_scale"), input.fetch(:guidance_scale)
    assert_equal settings.fetch("num_inference_steps"), input.fetch(:num_inference_steps)
    row = ledger_rows("series_start").fetch(0)
    assert_equal "identity", row.fetch("inference_profile")
  end

  def test_default_batch_contains_four_new_portraits
    run_series(series)

    assert_equal 4, @client.predictions.length
    assert_equal 4, ledger_rows("render").length
  end

  def test_default_series_uses_the_subject_pinned_lora_without_fallback
    run_series(series, count: 2)

    assert_equal ["owner/model:version-123"] * 2, @client.predictions.map(&:first)
  end

  def test_reference_engine_is_used_by_default_when_the_subject_has_sources
    subject_root = File.join(@dir, "subjects")
    FileUtils.mkdir_p(File.join(subject_root, "probe", "references"))
    File.write(File.join(subject_root, "probe", "references", "01.jpg"), "reference")
    client = ReferenceClient.new

    rendered = run_series(series(client:, subjects_root: subject_root), count: 1)

    assert_equal 1, rendered.length
    assert_equal "google/nano-banana-2.1", client.predictions.fetch(0).fetch(0)
    assert_equal "https://files.replicate.delivery/01.jpg",
                 client.predictions.fetch(0).fetch(1).fetch("image_input").first
    assert_equal 1, client.uploads.length
  end

  def test_render_records_the_arcface_likeness_result
    result = { "state" => "PASS", "metric" => "arcface_cosine", "similarity" => 0.72 }
    Studio::Lora::Judge.stub(:likeness, result) { series.run(count: 1) }

    assert_equal result, ledger_rows("render").fetch(0).fetch("likeness")
  end

  def test_each_named_subject_has_six_distinct_scenes
    %w[johann ragnhild merethe].each do |subject|
      scenes = (1..6).map { |number| Studio::Lora::Selfie.scene(number, subject:) }
      assert_equal 6, scenes.uniq.length, "#{subject} must have six distinct scenes"
    end
    refute_equal Studio::Lora::Selfie.scene(1, subject: "johann"), Studio::Lora::Selfie.scene(1, subject: "ragnhild")
    refute_equal Studio::Lora::Selfie.scene(1, subject: "ragnhild"), Studio::Lora::Selfie.scene(1, subject: "merethe")
  end

  def test_default_output_directory_is_the_lora_root
    box = Studio::Visual::SelfieSeries.new(subject: "probe", client: @client)
    assert_equal Studio::Visual::IdeaPicture::SUBJECTS, box.instance_variable_get(:@directory)
  end

  def test_legacy_replace_true_appends_without_deleting_any_prior_render_or_sidecar
    directory = File.join(@dir, "flat")
    FileUtils.mkdir_p(directory)
    old = File.join(directory, "probe_selfie_old.jpg")
    processed = File.join(directory, "postpro_probe_selfie_old_v1.jpg")
    sidecar = "#{old}.json"
    other = File.join(directory, "ragnhild_selfie_old.jpg")
    [old, processed, other].each { |path| File.write(path, "old") }
    File.write(sidecar, '{"preset":"portrait"}')

    box = Studio::Visual::SelfieSeries.new(
      subject: "probe", client: @client, directory:, ledger_path: File.join(@dir, "ledger.jsonl"),
    )
    rendered = run_series(box, count: 1, replace: true)

    [old, processed, sidecar, other].each { |path| assert File.file?(path), "#{path} must be retained" }
    assert_equal "old", File.read(old)
    refute ledger_rows("replace_delete").any?
    assert_equal 1, rendered.length
    assert File.file?(rendered.first)
    refute_equal old, rendered.first
  end

  def test_legacy_replace_true_does_not_touch_a_sidecar_symlink
    directory = File.join(@dir, "unsafe")
    FileUtils.mkdir_p(directory)
    old = File.join(directory, "probe_selfie_old.jpg")
    outside = File.join(@dir, "outside.json")
    File.write(old, "old")
    File.write(outside, '{"private":"other"}')
    File.symlink(outside, "#{old}.json")
    box = Studio::Visual::SelfieSeries.new(
      subject: "probe", client: @client, directory:, ledger_path: File.join(@dir, "ledger.jsonl")
    )

    rendered = run_series(box, count: 1, replace: true)

    assert File.file?(old)
    assert File.symlink?("#{old}.json")
    assert_equal '{"private":"other"}', File.read(outside)
    assert_equal 1, rendered.length
  end

  # test_replacement_plan_refuses_a_symlinked_sidecar_without_deleting_the_image
  # was retired with 771dc838: generation is append-only, replace: is a
  # compatibility keyword, and the replacement preflight it pinned no longer
  # exists. The append-only retention tests below carry the contract now.

  def test_partial_replacement_preserves_the_previous_series
    directory = File.join(@dir, "partial")
    FileUtils.mkdir_p(directory)
    old = File.join(directory, "probe_selfie_old.jpg")
    File.write(old, "previous")

    box = Studio::Visual::SelfieSeries.new(
      subject: "probe", client: FakeClient.new(fail_download_at: 2), directory:,
      ledger_path: File.join(@dir, "ledger.jsonl"),
    )
    rendered = run_series(box, count: 3, replace: true)

    assert_equal 2, rendered.length
    assert_equal "previous", File.read(old)
    refute ledger_rows("replace_delete").any?
    assert_equal 1, ledger_rows("render_attempt").length
  end

  def test_no_render_carries_the_film_model
    run_series(series, count: 2)

    models = @client.predictions.map(&:first)
    assert_equal 2, models.size
    refute_includes models, Studio::Visual::IdeaPicture::FILM, "a series never renders film"
  end

  def test_structured_shot_separates_capture_and_lab
    shot = { "scene" => "a person beside a window", "framing" => "head and shoulders",
             "distance" => "3m", "lens" => "85mm", "lighting" => "window",
             "moment" => "after_laugh", "gaze" => "eyes on the lens",
             "composition" => "one centre with clear depth", "preset" => "house" }
    plan = Studio::Lora::Craft.compile_shot(shot)
    assert_equal "house", plan.fetch("preset")
    assert_includes plan.fetch("prompt"), "three metres"
    assert_includes plan.fetch("prompt"), "sharp focus on the nearest eye"
    refute_includes plan.fetch("prompt"), "Kodak Portra"
    assert_raises(ArgumentError) { Studio::Lora::Craft.compile_shot(shot.merge("distance" => "selfie")) }
    assert_raises(ArgumentError) { Studio::Lora::Craft.compile_shot(shot.merge("preset" => "unknown")) }
  end

  def test_named_series_recipes_are_distinct_and_use_known_lab_presets
    %w[johann ragnhild merethe].each do |subject|
      recipes = (1..24).map { |n| Studio::Lora::Selfie.recipe(n, subject:) }
      assert_equal 24, recipes.map { |recipe| recipe.fetch("scene") }.uniq.size
      assert recipes.all? { |recipe| Studio::Lora::Craft::LABORATORY.include?(recipe.fetch("preset")) }
    end
  end

  def test_series_records_the_named_laboratory_and_unreviewed_status
    series.run(count: 1)
    row = ledger_rows("render").first
    assert_equal "house", row.fetch("recipe").fetch("preset")
    assert_equal "NOT_REVIEWED", row.fetch("review")
    assert_kind_of Integer, row.fetch("grade_seed")
  end

  def test_refinement_routes_identity_and_exposure_to_responsible_stages
    report = { "identity" => { "state" => "FAIL" },
               "faults" => [{ "metric" => "clipping", "remedy" => "inspect exposure" }] }
    hints = Studio::Lora::Judge.refinement(report)
    assert_equal %w[capture exposure_and_grade operator], hints.map { |hint| hint.fetch("stage") }
  end

  def test_generic_series_also_has_twenty_four_distinct_sittings
    recipes = (1..24).map { |n| Studio::Lora::Selfie.recipe(n) }
    assert_equal 24, recipes.map { |recipe| recipe.fetch("scene") }.uniq.size
  end

  def test_every_art_direction_has_twenty_four_distinct_valid_capture_plans
    Studio::Lora::Selfie::DIRECTIONS.each_key do |direction|
      recipes = (1..24).map { |n| Studio::Lora::Selfie.recipe(n, direction:) }
      assert_equal 24, recipes.map { |recipe| recipe.fetch("scene") }.uniq.size
      assert recipes.all? { |recipe| recipe.fetch("direction") == direction }
    end
    phone = Studio::Lora::Selfie.recipe(1, direction: "snapshot")
    assert_equal "selfie", phone.dig("shot", "distance")
    assert_equal "24mm", phone.dig("shot", "lens")
  end

  def test_named_render_refuses_invalid_seed_before_prediction
    picture = Studio::Visual::IdeaPicture.new(subject: "probe", client: @client, directory: @dir)
    assert_raises(ArgumentError) { picture.write("portrait", film: false, preset: "house", grade_seed: -1) }
    assert_empty @client.predictions
  end

  def test_prediction_budget_refuses_extra_dispatches
    budget = Studio::Visual::PredictionBudget.new(2)
    budget.consume!
    budget.consume!
    assert_equal 2, budget.used
    assert budget.exhausted?
    assert_raises(ArgumentError) { budget.consume! }
    assert_raises(ArgumentError) { Studio::Visual::PredictionBudget.new(9) }
  end

  def test_grade_only_fault_suggests_regrading_before_paid_capture
    report = { "faults" => [{ "metric" => "clipping", "origin" => "grade" }] }
    assert_equal "laboratory", Studio::Lora::Judge.refinement(report).first.fetch("stage")
  end

  def test_count_is_bounded
    error = assert_raises(ArgumentError) { series.run(count: Studio::Visual::SelfieSeries::LIMIT + 1) }
    assert_match(/between 1 and/, error.message)
    refute @client.predictions.any?, "a refused budget makes no paid call"
  end

  def test_a_failed_render_is_recorded_and_the_series_continues
    box = series(fail_download_at: 2)
    rendered = run_series(box, count: 3)

    assert_equal 2, rendered.size, "the network-lost scene is skipped, the series continues"
    attempts = ledger_rows("render_attempt")

    assert attempts.any?, "the failure lands in the ledger, not in silence"
    assert_match(/network lost/, attempts.first["error"])
  end

  def test_renders_are_recorded_in_the_subject_ledger
    run_series(series, count: 2)

    assert_equal 2, ledger_rows("render").size
    all_rows = File.readlines(File.join(@dir, "ledger.jsonl")).map { |line| JSON.parse(line) }
    row = ledger_rows("render").first

    assert_equal "probe", row["subject"]
    assert row["scene"].to_s.length > 10
    assert_equal 1, ledger_rows("series_start").length
    assert_equal 1, ledger_rows("render").map { |item| item["series_id"] }.uniq.length
    assert_equal ledger_rows("series_start").first["series_id"], row["series_id"]
    assert_equal 2, all_rows.first["count"]
    assert_equal 0o600, File.stat(File.join(@dir, "ledger.jsonl")).mode & 0o777
    assert_equal 0o700, File.stat(@dir).mode & 0o777
  end

  def test_the_scenes_carry_no_intimate_framing
    banned = %w[lingerie nude nudes naked topless shower bathtub underwear intimate bikini]
    text = Studio::Visual::SelfieSeries::SCENES.join("\n").downcase

    assert_empty banned.select { |word| text.include?(word) }
  end

  private

  def run_series(box, **options)
    Studio::Lora::Judge.stub(:likeness, { "state" => "INCONCLUSIVE", "reason" => "test" }) do
      box.run(**options)
    end
  end

  def ledger_rows(kind)
    path = File.join(@dir, "ledger.jsonl")
    File.file?(path) ? File.readlines(path).map { |line| JSON.parse(line) }.select { |row| row["kind"] == kind } : []
  end
end
