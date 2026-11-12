# frozen_string_literal: true

require "timeout"

module Master
  module Fix
    # One tiny request per live lane before the model phase, under a latency
    # budget. A lane that errors or answers too slowly is dropped for the run
    # (LaneQuota.drop_for_run!), so the first file does not discover it and the
    # next 1,650 do not rediscover it. The 2026-10-12 run stood 46 minutes at
    # 0 of 1651 files on free-class lanes that were alive and answering far too
    # slowly to repair anything.
    module LaneProbe
      PROMPT = "Reply with the single word OK."
      BUDGET_S = 20
      # Keep the ranked front while reserving four places for independent free/keyless providers.
      MAX_LANES = 12

      Row = Struct.new(:lane, :model, :status, :seconds, :detail, keyword_init: true)

      module_function

      def budget_s(model: nil)
        override = Integer(ENV["MASTER_FIX_PROBE_S"].to_s, exception: false)
        return override if override&.positive?

        lane = model.to_s.empty? ? nil : Master::Io::LaneState.lane_of(model)
        Integer(config.dig("lanes", lane, "probe_s") || config.fetch("default").fetch("probe_s"))
      end

      # Read on every call for the same reason FixTime does: a test that writes
      # its own limits must not depend on the order the suite ran in.
      def config
        section = Master.config_section("fix_time")
        raise "data/budgets.yml has no fix_time section" unless section.is_a?(Hash) && section["default"].is_a?(Hash)

        section
      end

      def enabled? = ENV["MASTER_FIX_PROBE"] != "0"

      # Probes the first model of each distinct live lane, in selection order,
      # and drops the lanes that are slow or dead. `ask` is
      # ->(model) { reply }, so a test drives it with a fake lane.
      # A nil `budget` reads the per-lane allowance (budget_s(model:)), so a
      # lane that answers in a minute is not dropped by the default's seconds.
      def run(models:, ask:, budget: nil, max_lanes: MAX_LANES, stop_on_success: false,
              clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        rows = []
        pick(models, max_lanes).each do |model|
          row = probe(model, ask:, budget: budget || budget_s(model:), clock:)
          rows << row
          Master::Io::LaneQuota.drop_for_run!(row.lane, "probe #{row.status}: #{row.detail}") unless row.status == :ok
          break if stop_on_success && row.status == :ok
        end
        rows.each { |row| say(row) } if Master::Trace::Dmesg.verbose?
        say_verdict(rows)
        rows
      end

      # A dead paid prefix must not hide the keyless recovery floor.
      def pick(models, max_lanes)
        lanes = Master::Io::LaneState
        ordered = Master::Io::LaneSelection.order(Array(models)).uniq { |model| lanes.lane_of(model) }
        return ordered.first(max_lanes) if ordered.length <= max_lanes

        free, preferred = ordered.partition do |model|
          Master::Io::LaneSelection.kind(model) == :free
        end
        free_slots = [free.length, [(max_lanes / 3.0).ceil, 4].min].min
        (preferred.first(max_lanes - free_slots) + free.first(free_slots)).first(max_lanes)
      end

      def probe(model, ask:, budget:, clock:)
        lane = Master::Io::LaneState.lane_of(model)
        started = clock.call
        Fiber[:master_operation] = :lane_probe
        reply = Timeout.timeout(budget) { ask.call(model) }
        seconds = clock.call - started
        return Row.new(lane:, model:, status: :empty, seconds:, detail: "empty reply") if reply.to_s.strip.empty?
        return Row.new(lane:, model:, status: :slow, seconds:, detail: "answered in #{seconds.round(1)}s, budget #{budget}s") if seconds > budget

        Row.new(lane:, model:, status: :ok, seconds:, detail: "answered")
      rescue Timeout::Error
        Row.new(lane:, model:, status: :slow, seconds: clock.call - started, detail: "no answer within #{budget}s")
      rescue StandardError => e
        Row.new(lane:, model:, status: :dead, seconds: clock.call - started, detail: "#{e.class}: #{e.message}"[0, 120])
      ensure
        Fiber[:master_operation] = nil
      end

      def say(row)
        Master::Trace::Dmesg.status("fix0", "lane probe #{row.lane} (#{row.model}) #{row.status} #{row.seconds.round(1)}s, #{row.detail}")
      end

      def say_verdict(rows)
        winner = rows.find { |row| row.status == :ok }
        text = if winner
                 "lane probe: #{Master::Io::LaneSelection.provider(winner.model)} answered after #{rows.size} check(s)"
               else
                 "lane probe: no reply from #{rows.size} eligible provider(s)"
               end
        Master::Trace::Dmesg.status("fix0", text)
      end

      # The probe a run uses: a bare ask on the named lane, no failover, no law preamble.
      def ask_with(agent)
        ->(model) { agent.ask_once(PROMPT, model:, failover: false, law: false) }
      end
    end
  end
end
