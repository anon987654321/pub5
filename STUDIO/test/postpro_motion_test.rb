# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../postpro/motion"

class TestPostproMotionFrameContext < Minitest::Test
  def test_context_records_the_frame_and_freezes_nested_offsets
    context = Postpro::Motion::FrameContext.new(
      index: 12,
      time_seconds: 0.5,
      gate_weave: { x: -0.25, y: 0.75 }
    )

    assert_equal 12, context.index
    assert_in_delta 0.5, context.time_seconds, 1e-12
    assert_equal({ x: -0.25, y: 0.75 }, context.gate_weave)
    assert_predicate context, :frozen?
    assert_predicate context.gate_weave, :frozen?
    assert_raises(FrozenError) { context.gate_weave[:x] = 9.0 }
  end

  def test_contexts_do_not_share_mutable_frame_state
    first = Postpro::Motion::FrameContext.new(
      index: 0, time_seconds: 0.0, gate_weave: { x: 0.1, y: 0.2 }
    )
    second = Postpro::Motion::FrameContext.new(
      index: 1, time_seconds: 1.0 / 24.0, gate_weave: { x: -0.3, y: 0.4 }
    )

    refute_same first, second
    refute_same first.gate_weave, second.gate_weave
    assert_equal({ x: 0.1, y: 0.2 }, first.gate_weave)
    assert_equal({ x: -0.3, y: 0.4 }, second.gate_weave)
    refute_respond_to Postpro::Motion, :gate_weave_offset
    refute_respond_to Postpro::Motion, :gate_weave_offset=
  end

  def test_context_rejects_invalid_frame_coordinates_and_non_finite_offsets
    assert_raises(ArgumentError) do
      Postpro::Motion::FrameContext.new(index: -1, time_seconds: 0.0)
    end
    assert_raises(ArgumentError) do
      Postpro::Motion::FrameContext.new(index: 0, time_seconds: Float::INFINITY)
    end
    assert_raises(ArgumentError) do
      Postpro::Motion::FrameContext.new(
        index: 0, time_seconds: 0.0, gate_weave: { x: Float::NAN, y: 0.0 }
      )
    end
  end

  def test_frame_grain_modes_remain_deterministic
    assert_equal 42, Postpro::Motion.seed_for(0, 42, grain: :moving)
    assert_equal 43, Postpro::Motion.seed_for(1, 42, grain: :moving)
    assert_equal 42, Postpro::Motion.seed_for(1, 42, grain: :hold)
    assert_raises(ArgumentError) do
      Postpro::Motion.seed_for(0, 42, grain: :random)
    end
  end
end
