# frozen_string_literal: true

require_relative "minitest_helper"
require "digest"
require "json"
require "tmpdir"

begin
  require_relative "../../lora/quality"
rescue LoadError => error
  warn "skipping provenance tests: #{error.message}"
  return
end

# A likeness verdict covers the exact bytes it was made on. If a reviewed
# render is edited afterwards, the receipt must stop vouching for it - this
# pins the drift detection.
class TestStudioLoraProvenance < Minitest::Test
  Quality = Studio::Lora::Quality

  def test_verdict_mapping
    assert_equal "UNKNOWN", Quality.provenance_verdict(nil)
    assert_equal "PROVENANCE_INTACT", Quality.provenance_verdict([{ "status" => "MATCH" }])
    assert_equal "PROVENANCE_DRIFT", Quality.provenance_verdict([{ "status" => "MATCH" }, { "status" => "CHANGED" }])
    assert_equal "PROVENANCE_DRIFT", Quality.provenance_verdict([{ "status" => "MISSING" }])
  end

  def test_intact_when_files_match_the_receipt
    Dir.mktmpdir do |dir|
      receipt_path, = write_review_fixture(dir)
      state = Quality.provenance_check({ "receipt_path" => receipt_path })
      assert_equal "PROVENANCE_INTACT", state.fetch("state")
      assert_equal %w[MATCH MATCH], state.fetch("images").map { |row| row["status"] }
    end
  end

  def test_drift_when_a_reviewed_file_changes_afterwards
    Dir.mktmpdir do |dir|
      receipt_path, render = write_review_fixture(dir)
      File.binwrite(render, "edited after review")
      File.chmod(0o600, render)
      state = Quality.provenance_check({ "receipt_path" => receipt_path })
      assert_equal "PROVENANCE_DRIFT", state.fetch("state")
      assert_equal "CHANGED", state.fetch("images").last.fetch("status")
    end
  end

  def test_drift_when_a_reviewed_file_disappears
    Dir.mktmpdir do |dir|
      receipt_path, render = write_review_fixture(dir)
      File.delete(render)
      state = Quality.provenance_check({ "receipt_path" => receipt_path })
      assert_equal "PROVENANCE_DRIFT", state.fetch("state")
      assert_equal "MISSING", state.fetch("images").last.fetch("status")
    end
  end

  def test_unknown_for_legacy_receipts_without_hashes
    Dir.mktmpdir do |dir|
      receipt_path = File.join(dir, "review.json")
      File.write(receipt_path, JSON.pretty_generate({ "images" => [{ "file" => "a.jpg" }] }))
      state = Quality.provenance_check({ "receipt_path" => receipt_path })
      assert_equal "UNKNOWN", state.fetch("state")
    end
  end

  private

  def write_review_fixture(dir)
    holdout = File.join(dir, "holdout.jpg")
    render = File.join(dir, "render.jpg")
    File.binwrite(holdout, "holdout bytes")
    File.binwrite(render, "render bytes")
    [holdout, render].each { |path| File.chmod(0o600, path) }
    receipt = {
      "images" => [
        { "role" => "HOLDOUT_REFERENCE", "file" => "holdout.jpg", "relative_path" => "holdout.jpg",
          "sha256" => Digest::SHA256.file(holdout).hexdigest },
        { "role" => "FINAL", "file" => "render.jpg", "relative_path" => "render.jpg",
          "sha256" => Digest::SHA256.file(render).hexdigest },
      ],
    }
    receipt_path = File.join(dir, "review.json")
    File.write(receipt_path, JSON.pretty_generate(receipt))
    [receipt_path, render]
  end
end
