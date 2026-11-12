# frozen_string_literal: true

begin
  require "rufus/scheduler"
  RUFUS_AVAILABLE = true
rescue LoadError
  RUFUS_AVAILABLE = false
end

module Master
  class SchedulerUnavailableError < StandardError; end

  # Runs persisted schedules via Rufus::Scheduler. Jobs execute their prompt
  # through a callback (typically Agent#run) in their own thread, then the
  # result is recorded back into the ScheduleStore.
  #
  # Kept decoupled from Agent so it can be tested with a stub callback.
  class Scheduler
    def initialize(store:, run_prompt:, on_result: nil)
      raise SchedulerUnavailableError,
            "gem 'rufus-scheduler' is required for scheduling" unless RUFUS_AVAILABLE

      @store = store
      @run_prompt = run_prompt # -> (prompt, thread_id) { answer_string }
      @on_result = on_result   # -> (name, result_string) { ... }
      @sch = Rufus::Scheduler.new
    end

    # Load all enabled, persisted schedules. Returns { loaded:, failed: [[name, why]] }.
    def boot!
      loaded = 0
      failed = []
      @store.list.select { |e| e[:enabled] }.each do |entry|
        begin
          register(entry)
          loaded += 1
        rescue StandardError => e
          failed << [entry[:name], e.message]
        end
      end
      { loaded: loaded, failed: failed }
    end

    def register(entry)
      kind, _, expr = entry[:schedule].to_s.partition(":")
      name = entry[:name]

      runner = lambda do
        result = begin
          @run_prompt.call(entry[:prompt], entry[:thread_id])
        rescue StandardError => e
          "ERROR: #{e.class}: #{e.message}"
        end
        @store.mark_run(entry[:id], result)
        @on_result&.call(name, result.to_s)
      end

      case kind
      when "cron"  then @sch.cron(expr, tags: [name], &runner)
      when "every" then @sch.every(expr, tags: [name], &runner)
      when "at"    then @sch.at(expr, tags: [name], &runner)
      else raise ScheduleError, "unknown schedule kind #{kind.inspect} (use cron:/every:/at:)"
      end
      name
    end

    def unregister(name)
      @sch.jobs(tag: name).each(&:unschedule)
      self
    end

    def shutdown
      @sch.shutdown
      self
    end
  end
end
