# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../lib/fix/visual_lane_world"

# A review must judge this run's render. SweepEvidence names the manifest the
# sweep reported; only when the sweep names none does it fall back to the
# newest manifest on disk, and that fallback must not reach back past the
# process — a previous run's render is not evidence about the current tree.
class TestSweepEvidenceFreshness < Minitest::Test
  Evidence = Master::Fix::VisualLaneWorld::SweepEvidence
  Result = Data.define(:warnings, :failures, :soft_failures) do
    def initialize(warnings: [], failures: [], soft_failures: []) = super
  end

  def manifest(dir, rows)
    path = File.join(dir, "manifest.json")
    File.write(path, JSON.generate("results" => rows))
    path
  end

  def test_the_named_manifest_wins_over_anything_on_disk
    Dir.mktmpdir do |dir|
      named = manifest(dir, [{ "app" => "amber", "surface" => "s", "viewport" => "w390",
                               "url" => "/", "screenshot" => "/named.png" }])
      result = Result.new(warnings: ["browser_diagnostics: evidence manifest #{named}"])

      assert_equal named, Evidence.new.send(:manifest_for, result)
    end
  end

  def test_an_unnamed_sweep_refuses_a_manifest_older_than_this_process
    Dir.mktmpdir do |dir|
      stale = manifest(dir, [{ "app" => "amber", "surface" => "s", "viewport" => "w390",
                               "url" => "/old", "screenshot" => "/old.png" }])
      File.utime(Time.now - 3600, Time.now - 3600, stale)
      base = File.expand_path(dir)
      old = ENV["CHECK_BROWSER_DIAGNOSTICS_OUTPUT"]
      ENV["CHECK_BROWSER_DIAGNOSTICS_OUTPUT"] = base
      begin
        # The fallback scans <base>/*/manifest.json, so the stale file sits in a run dir.
        run_dir = File.join(base, "20260101T000000Z-1")
        FileUtils.mkdir_p(run_dir)
        FileUtils.mv(stale, File.join(run_dir, "manifest.json"))
        File.utime(Time.now - 3600, Time.now - 3600, File.join(run_dir, "manifest.json"))

        assert_nil Evidence.new.send(:manifest_for, Result.new),
                   "a manifest older than the process must not be reviewed as current"
      ensure
        old ? ENV["CHECK_BROWSER_DIAGNOSTICS_OUTPUT"] = old : ENV.delete("CHECK_BROWSER_DIAGNOSTICS_OUTPUT")
      end
    end
  end

  def test_an_unnamed_sweep_accepts_a_manifest_written_by_this_run
    Dir.mktmpdir do |dir|
      base = File.expand_path(dir)
      run_dir = File.join(base, "20990101T000000Z-1")
      FileUtils.mkdir_p(run_dir)
      fresh = manifest(run_dir, [{ "app" => "amber", "surface" => "s", "viewport" => "w390",
                                   "url" => "/new", "screenshot" => "/new.png" }])
      old = ENV["CHECK_BROWSER_DIAGNOSTICS_OUTPUT"]
      ENV["CHECK_BROWSER_DIAGNOSTICS_OUTPUT"] = base
      begin
        assert_equal fresh, Evidence.new.send(:manifest_for, Result.new)
      ensure
        old ? ENV["CHECK_BROWSER_DIAGNOSTICS_OUTPUT"] = old : ENV.delete("CHECK_BROWSER_DIAGNOSTICS_OUTPUT")
      end
    end
  end
end
