# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"

# The scorecard ends every /fix run and writes the residual the next run resumes
# from. It crashed the whole run with `uninitialized constant
# ...PipelinePassStageAssembly::Residual`, because that module sits at
# Master::CLI::PipelinePassStageAssembly and a bare `Residual` resolved against
# the wrong nesting. The test calls the real method so the constant is resolved
# the way the run resolves it, not by name from the top level.
class TestPassScorecardLine < Minitest::Test
  def pass(residual:)
    fix_loop = Object.new
    fix_loop.define_singleton_method(:gap_count) { 0 }
    Master::CLI::Pipeline::Pass.new(scanner: nil, fix_loop:, root: Master::ROOT).tap do |built|
      built.instance_variable_set(:@resolved, "RAILS")
      built.instance_variable_set(:@scored, { outcome: :partial, delivered: 2 })
      built.instance_variable_set(:@observation_totals, { "obs0" => 5, "obs1" => 3 })
    end
  end

  def test_scorecard_line_resolves_the_residual_writer_and_records_it
    Dir.mktmpdir do |dir|
      residual = File.join(dir, "fix_residual.json")
      ENV["MASTER_FIX_RESIDUAL"] = residual
      begin
        line = pass(residual:).send(:scorecard_line)

        assert_includes line, "fix partial"
        assert_includes line, "2 commit(s) delivered"
        written = JSON.parse(File.read(residual))
        assert_equal line, written.fetch("RAILS").fetch("scorecard"),
                     "the run's own scorecard must be the one the next run reads back"
      ensure
        ENV.delete("MASTER_FIX_RESIDUAL")
      end
    end
  end
end
