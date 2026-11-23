# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "minitest_helper"
require_relative "../../lora/quality"

class TestStudioLoraQuality < Minitest::Test
  Quality = Studio::Lora::Quality

  def setup
    @root = Dir.mktmpdir("studio-lora-quality-")
    @subject = File.join(@root, "probe")
    @dataset = File.join(@subject, "dataset")
    @evaluation = File.join(@subject, Quality.evaluation_directory_name)
    [@subject, @dataset, @evaluation].each do |directory|
      FileUtils.mkdir_p(directory, mode: 0o700)
      File.chmod(0o700, directory)
    end
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_profile_catalogue_is_valid_and_never_claims_a_winner
    report = Quality.audit_configuration
    assert_equal "PASS", report.fetch("state")
    assert_equal "balanced", report.fetch("default_profile")
    assert_equal %w[identity balanced detail draft], report.fetch("profiles").map { |item| item.fetch("name") }
    assert report.fetch("profiles").all? { |item| item.fetch("status") == "UNBENCHMARKED" }
  end

  def test_holdout_inventory_requires_five_private_nonduplicate_images_disjoint_from_training
    12.times { |index| write_private(@dataset, "train-#{index}.jpg", "training #{index}") }
    5.times { |index| write_private(@evaluation, "holdout-#{index}.jpg", "evaluation #{index}") }

    images = Quality.evaluation_files(subject: "probe", root: @root)
    assert_equal 5, images.length
    assert images.all? { |path| path.start_with?("#{@evaluation}/") }
  end

  def test_holdout_inventory_rejects_training_overlap
    12.times { |index| write_private(@dataset, "train-#{index}.jpg", "training #{index}") }
    5.times { |index| write_private(@evaluation, "holdout-#{index}.jpg", "evaluation #{index}") }
    File.write(File.join(@evaluation, "duplicate.jpg"), File.read(File.join(@dataset, "train-0.jpg")), mode: "w", perm: 0o600)

    error = assert_raises(Quality::Error) { Quality.evaluation_files(subject: "probe", root: @root) }
    assert_match(/overlaps the training dataset/, error.message)
  end

  def test_holdout_inventory_rejects_insecure_files_and_missing_holdout
    12.times { |index| write_private(@dataset, "train-#{index}.jpg", "training #{index}") }
    error = assert_raises(Quality::Error) { Quality.evaluation_files(subject: "probe", root: @root) }
    assert_match(/at least 5/, error.message)

    5.times { |index| write_private(@evaluation, "holdout-#{index}.jpg", "evaluation #{index}") }
    File.chmod(0o644, File.join(@evaluation, "holdout-0.jpg"))
    error = assert_raises(Quality::Error) { Quality.evaluation_files(subject: "probe", root: @root) }
    assert_match(/owner-only file/, error.message)
  end

  private

  def write_private(directory, filename, content)
    path = File.join(directory, filename)
    File.write(path, content, mode: "w", perm: 0o600)
    File.chmod(0o600, path)
    path
  end
end
