# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/design_run"

class TestDesignRun < Minitest::Test
  RUN = Operator::DesignRun
  Surface = Struct.new(:id, :pixel_snapshot)
  Round = Struct.new(:outcome)

  def said(kept, surfaces)
    lines = []
    RUN.stub(:say, ->(text) { lines << text }) { RUN.baselines_note(kept, surfaces) }
    lines
  end

  # Baseline approval is the operator's, so a run that kept an edit names what to review first.
  def test_a_kept_edit_names_the_measured_surfaces_that_carry_an_approved_png
    surfaces = [Surface.new("amber/home/desktop", true), Surface.new("amber/feed/desktop", false)]
    lines = said([Round.new(:kept)], surfaces)

    assert_match(/differ on: amber\/home\/desktop\z/, lines.first)
    assert_match(/approve_visual_baselines\.rb --manifest/, lines.last)
  end

  def test_nothing_is_said_without_a_kept_edit_or_without_an_approved_png
    assert_empty said([], [Surface.new("amber/home/desktop", true)])
    assert_empty said([Round.new(:kept)], [Surface.new("amber/feed/desktop", false)])
  end

  def transaction(root, path, id:)
    Master::Fix::Transaction.new(root:, paths: [path], id:).tap(&:begin!)
  end

  def head(root)
    IO.popen(["git", "-C", root, "rev-parse", "HEAD"], &:read).strip
  end

  def git(root, *args) = system("git", "-C", root, *args, out: File::NULL, err: File::NULL)

  def write_all(root, files) = files.each { |rel, text| File.write(File.join(root, rel), text) }

  # A checkout whose MASTER declares data/laws.yml sacred, with laws.yml and app.css edited since its base commit.
  def edited_checkout(root)
    git(root, "init", "-q")
    git(root, "config", "user.email", "test@example.invalid")
    git(root, "config", "user.name", "test")

    FileUtils.mkdir_p(File.join(root, "MASTER", "data"))
    File.write(File.join(root, "MASTER", "data", "soul.yml"), "absolute:\n  sacred_paths:\n    - data/laws.yml\n")
    write_all(root, "MASTER/data/laws.yml" => "a: 1\n", "app.css" => "a {}\n")
    git(root, "add", ".")
    git(root, "commit", "-q", "-m", "base")

    write_all(root, "MASTER/data/laws.yml" => "a: 2\n", "app.css" => "b {}\n")
  end

  # Consent is settled once in GeometryProbe.with_browser, which this run opens
  # the browser through, so the loop carries no consent script of its own.
  def test_the_run_carries_no_consent_script_of_its_own
    refute RUN.const_defined?(:DECIDED_CONSENT), "consent lives in GeometryProbe, not here"
  end

  # A design run commits through the transaction receipt and private-index path.
  def test_commit_refuses_a_sacred_path_and_delivers_an_ordinary_one
    Dir.mktmpdir do |root|
      edited_checkout(root)
      lines = []
      sacred_path = File.join(root, "MASTER", "data", "laws.yml")
      sacred = transaction(root, sacred_path, id: "design-#{'a' * 20}")
      ordinary_path = File.join(root, "app.css")
      ordinary = transaction(root, ordinary_path, id: "design-#{'b' * 20}")

      RUN.stub(:say, ->(text) { lines << text }) do
        refute RUN.commit(sacred_path, "design: laws", root:, transaction: sacred)
        assert sacred.rollback!.ok?
        assert RUN.commit(ordinary_path, "design: css", root:, transaction: ordinary)
      end

      assert_match(/data\/laws\.yml is sacred/, lines.first)
      assert_equal "design: css\nbase\n", IO.popen(["git", "-C", root, "log", "--format=%s"], &:read)
      refute ordinary.active?
    end
  end

  def test_report_returns_failure_when_a_partial_run_has_delivery_errors
    Dir.mktmpdir do |root|
      edited_checkout(root)
      result = Struct.new(:outcome, :number, :surface, :why, :before, :after)
      results = [
        result.new(:kept, 1, "brgen/home", "more room", 40.0, 60.0),
        Round.new(:delivery_failed),
      ]
      lines = []
      status = RUN.stub(:say, ->(text) { lines << text }) do
        RUN.report(results, root:, before: head(root), surfaces: [])
      end

      assert_equal 1, status
      assert_match(/design run incomplete: delivery_failed/, lines.join("\n"))
      assert_match(/1 edit\(s\) kept in 2 round\(s\)/, lines.join("\n"))
    end
  end
end
