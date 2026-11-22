# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/master/time"

class TestMasterTime < Minitest::Test
  def test_time_seam_exposes_wall_and_monotonic_clocks
    assert_kind_of ::Time, Master::Clock.now
    assert_kind_of ::Time, Master::Clock.utc_now
    assert_kind_of Numeric, Master::Clock.monotonic
  end
end
