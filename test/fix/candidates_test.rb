# frozen_string_literal: true

require_relative "fix_helper"
require "timeout"

# Moved from pub4 MASTER/test/test_candidate_threads.rb (f52307b568): the
# concurrent candidates started with no thread-locals and outlived a Timeout.
# The model gate, lane cool-off and CLI usage tests of this file's pub4
# sources (test_fix_model_gate, test_fix_lane_cool_off, test_cli_lane_usage)
# moved with that code to test/models/.
class FixCandidatesTest < Minitest::Test
  def test_each_candidate_sees_the_parents_thread_locals
    Thread.current[:fix_retry_note] = "the diff touched line 900"
    rows = Fix::Candidates.collect(3) { |_| Thread.current[:fix_retry_note] }

    assert_equal ["the diff touched line 900"] * 3, rows
  ensure
    Thread.current[:fix_retry_note] = nil
  end

  def test_a_candidate_still_running_when_the_caller_gives_up_is_killed
    workers = Queue.new
    assert_raises(Timeout::Error) do
      Timeout.timeout(0.3) do
        Fix::Candidates.collect(2) do
          workers << Thread.current
          sleep 30
        end
      end
    end
    threads = Array.new(2) { workers.pop(timeout: 2) }
    threads.each { |t| t.join(2) }
    refute threads.any?(&:alive?), "a candidate thread outlived the caller"
  end
end
