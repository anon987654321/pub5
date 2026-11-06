# frozen_string_literal: true

require "etc"

module Models
  # Paces a model call before it is made. Two things burned files in pub4's
  # /fix on 2026-11-05:
  #
  # A run pinned to one lane (claude-cli, no failover) met the five-minute
  # cool-off, and every file in it failed at once, "offline: no lane answers".
  # When every candidate is in a cool-off, the gate now waits it out, polling,
  # so the next call meets an answering lane.
  #
  # The malformed replies began with the 8-core Mac at load 12.9. A host whose
  # one-minute load is over LOAD_PER_CPU per CPU gets up to LOAD_WAIT_MAX_S to
  # come down.
  #
  # With a deadline (a monotonic time, as a /fix run has) nothing waits into
  # its last RESERVE_S, which is for the run's proof. Each poll says so in one
  # dmesg line, so a paced run is not read as a stalled one.
  class Gate
    POLL_S = 15
    LOAD_WAIT_MAX_S = 300
    LOAD_PER_CPU = 1.5
    RESERVE_S = 120

    # The one-minute load average from sysctl(8) vm.loadavg, which macOS
    # prints as "{ 1.23 1.10 1.00 }" and OpenBSD as "1.23 1.10 1.00".
    def self.host_load(world)
      run = world.exec("sysctl", "-n", "vm.loadavg", timeout: 5)
      run.ok? ? run.out[/\d+(?:\.\d+)?/]&.to_f : nil
    rescue Core::Refusal
      nil
    end

    def initialize(lanes:, load: -> {}, cpus: Etc.nprocessors, say: ->(_line) {}, sleeper: ->(s) { sleep(s) },
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, deadline: nil)
      @lanes = lanes
      @load = load
      @ceiling = LOAD_PER_CPU * cpus
      @say = say
      @sleeper = sleeper
      @clock = clock
      @deadline = deadline
    end

    # Seconds waited, 0 when the lanes answer and the host is quiet.
    def before_call(models)
      waited = wait_out_cool_off(Array(models))
      waited + wait_for_load
    end

    private

    def wait_out_cool_off(models)
      return 0 if models.empty?

      waited = 0
      limit = models.map { |m| @lanes.wait_s(m) }.min.to_i + POLL_S
      while models.all? { |m| @lanes.cooling?(m) } && waited < limit && time_left?
        waited += pause("#{@lanes.lane_of(models.first)} is cooling off; waiting #{POLL_S}s instead of failing the call")
      end
      waited
    end

    def wait_for_load
      waited = 0
      while (load = @load.call) && load > @ceiling && waited < LOAD_WAIT_MAX_S && time_left?
        waited += pause(format("load %<load>.1f is over %<ceiling>.1f; waiting %<poll>ds before the model call",
                               load:, ceiling: @ceiling, poll: POLL_S))
      end
      waited
    end

    def pause(line)
      @say.call("gate0: #{line}")
      @sleeper.call(POLL_S)
      POLL_S
    end

    def time_left? = @deadline.nil? || @deadline - @clock.call > RESERVE_S + POLL_S
  end
end
