# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require "fileutils"
require_relative "../lora/review"

class TestStudioLoraReview < Minitest::Test
  def setup
    @root = Dir.mktmpdir("studio-lora-review-")
    @subject = File.join(@root, "johann")
    FileUtils.mkdir_p(@subject, mode: 0o700)
    File.chmod(0o700, @subject)
    @builder = Studio::Lora::Review::Builder.new(subject: "johann", root: @root)
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_render_inventory_selects_only_final_private_selfie_outputs
    6.times do |index|
      write_private(File.join(@root, "postpro_johann_selfie_#{index + 1}_v1.jpg"))
    end
    write_private(File.join(@root, "postpro_ragnhild_selfie_01_v1.jpg"))
    write_private(File.join(@root, "postpro_johann_film_01_v1.jpg"))
    write_private(File.join(@root, "johann_reference.jpg"))

    paths = @builder.render_files
    assert_equal 6, paths.length
    assert paths.all? { |path| File.basename(path).start_with?("postpro_johann_selfie_") }
  end

  def test_reference_inventory_uses_only_private_dataset_images
    dataset = File.join(@subject, "dataset")
    FileUtils.mkdir_p(dataset, mode: 0o700)
    File.chmod(0o700, dataset)
    5.times { |index| write_private(File.join(dataset, "source-#{index}.jpg")) }
    File.write(File.join(dataset, "source-0.txt"), "johann_lora", mode: "w", perm: 0o600)

    references = @builder.reference_files
    assert_equal 3, references.length
    assert_equal %w[source-0.jpg source-2.jpg source-4.jpg], references.map { |path| File.basename(path) }
  end

  def test_review_requires_exactly_six_final_renders
    error = assert_raises(Studio::Lora::Review::Error) do
      @builder.validate_render_count!(["one.jpg"])
    end
    assert_match(/expected 6/, error.message)
    assert @builder.validate_render_count!(Array.new(6, "render.jpg"))
  end

  private

  def write_private(path)
    File.write(path, "synthetic image bytes", mode: "w", perm: 0o600)
    File.chmod(0o600, path)
  end
end
