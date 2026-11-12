# frozen_string_literal: true

# Domain-neutral, seeded motion for analog processes.
#
# A two-pole, mean-reverting filtered-noise process. Unlike a looping LFO it
# has no period; unlike an unconstrained random walk it cannot drift without
# bound. rate_hz is the low-pass corner, depth is expressed in the caller's
# units, and one instance advances one sample at a time. The same source can
# describe tape-speed variation in audio samples and gate movement in video
# frames without pretending those domains share pixel/sample scales.
module AnalogCore
  class StochasticWalk
    LIMIT_SIGMA = 3.0
    MAX_WARM_UP = 2_000_000

    def initialize(rate_hz:, depth:, rng:, sample_rate: 44_100)
      @rate = Float(rate_hz)
      @depth = Float(depth)
      @sample_rate = Float(sample_rate)
      @rng = rng

      unless @rate.finite? && @depth.finite? && @sample_rate.finite? &&
             @rate >= 0.0 && @depth >= 0.0 && @sample_rate.positive? &&
             @sample_rate <= 768_000.0 && @rate < @sample_rate / 2.0
        raise ArgumentError, "rate, depth or sample rate is outside the supported range"
      end
      raise ArgumentError, "rng must respond to rand" unless @rng.respond_to?(:rand)

      @alpha = @rate.zero? ? 0.0 : 1.0 - Math.exp(-2.0 * Math::PI * @rate / @sample_rate)
      @state_a = 0.0
      @state_b = 0.0
      @normalizer = normalization
      warm_up unless @alpha.zero?
    rescue TypeError, RangeError => e
      raise ArgumentError, "invalid stochastic-walk parameters: #{e.message}"
    end

    def next_value
      return 0.0 if @alpha.zero? || @depth.zero?

      noise = @rng.rand * 2.0 - 1.0
      @state_a += @alpha * (noise - @state_a)
      @state_b += @alpha * (@state_a - @state_b)
      (@state_b * @normalizer).clamp(-LIMIT_SIGMA, LIMIT_SIGMA) * @depth
    end

    def run(length)
      count = Integer(length)
      raise ArgumentError, "length must not be negative" if count.negative?

      Array.new(count) { next_value }
    rescue TypeError, ArgumentError => e
      raise e if e.message == "length must not be negative"

      raise ArgumentError, "length must be a nonnegative integer"
    end

    private

    # For two cascaded one-pole filters driven by uniform [-1, 1] noise,
    # this is the exact stationary variance of the discrete process.
    def normalization
      return 0.0 if @alpha.zero?

      pole = 1.0 - @alpha
      variance = (@alpha**4 * (1.0 + pole**2)) /
                 (3.0 * (1.0 - pole**2)**3)
      1.0 / Math.sqrt(variance)
    end

    # Start near stationarity rather than fading in from zero. Refuse pathological
    # sub-Hz/sample-rate combinations that would require unbounded setup work.
    def warm_up
      samples = (8.0 / @alpha).ceil
      raise ArgumentError, "rate is too low for this sample rate" if samples > MAX_WARM_UP

      samples.times do
        noise = @rng.rand * 2.0 - 1.0
        @state_a += @alpha * (noise - @state_a)
        @state_b += @alpha * (@state_a - @state_b)
      end
    end
  end
end
