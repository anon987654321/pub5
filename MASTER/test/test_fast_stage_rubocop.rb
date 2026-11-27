# frozen_string_literal: true

require_relative "test_helper"

class TestFastStageRubocop < Minitest::Test
  class Harness
    include Master::Fix::FixLoop::PassRunner::FastStage

    def initialize(root) = @root = root
    def stuck(out, _files) = uncorrected_files(JSON.parse(out).fetch("files"), @root)
  end

  ROOT = "/repo/MASTER"

  def report(*entries) = JSON.generate("files" => entries)

  def test_only_retained_corrections_count_as_progress
    Dir.mktmpdir do |root|
      kept, reverted, unchanged = %w[kept.rb reverted.rb unchanged.rb].map { |name| File.join(root, name) }
      files = [kept, reverted, unchanged]
      files.each { |path| File.write(path, "x=1\n") }
      harness = Harness.new(root)
      guard = Master::Fix::AutofixGuard
      harness.stub(:rubocop_candidates, files) do
        harness.stub(:rubocop_run, ->(*) {
          File.write(kept, "x = 1\n")
          File.write(reverted, "x = 1\n")
          { kept => 2, reverted => 3, unchanged => 4 }
        }) do
          harness.stub(:rubocop_verdict, ->(path, *) { "regression" if path == reverted }) do
            guard.stub(:mode, "on") do
              guard.stub(:note_written, nil) do
                guard.stub(:note_refused, nil) do
                  assert_equal 2, harness.send(:rubocop_pass, files, root)
                end
              end
            end
          end
        end
      end
      assert_equal "x = 1\n", File.read(kept)
      assert_equal "x=1\n", File.read(reverted)
    end
  end

  def test_a_file_whose_offenses_were_all_corrected_is_not_stuck
    out = report(
      { "path" => "lib/a.rb", "offenses" => [{ "corrected" => true }] },
      { "path" => "lib/b.rb", "offenses" => [] },
    )

    assert_empty Harness.new(ROOT).stuck(out, [])
  end

  def test_a_file_with_one_uncorrected_offense_is_stuck
    out = report(
      { "path" => "lib/a.rb", "offenses" => [{ "corrected" => true }, { "corrected" => false }] },
      { "path" => "lib/b.rb", "offenses" => [{ "corrected" => true }] },
    )

    assert_equal ["#{ROOT}/lib/a.rb"], Harness.new(ROOT).stuck(out, [])
  end
end
