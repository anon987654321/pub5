# frozen_string_literal: true

module Master
  module Tools
    # schedule_create / schedule_list / schedule_delete: let the agent manage
    # recurring prompts. Schedules are persisted (ScheduleStore) and executed
    # by the Scheduler runtime; a running Scheduler registers/unregisters
    # live via the optional callbacks.
    class ScheduleCreate < Tool
      def initialize(store, on_create: nil)
        @store = store
        @on_create = on_create # -> (entry_hash) { ... } registers with the live scheduler
      end

      def name
        "schedule_create"
      end

      def description
        "Create a recurring or one-shot task. Schedule format: 'cron:<expression>' " \
          "(e.g. cron:0 9 * * *), 'every:<duration>' (e.g. every:30m), or 'at:<time>' " \
          "(e.g. at:2026-12-24 09:00). The prompt is executed by MASTER on schedule."
      end

      def parameters
        {
          type: "object",
          properties: {
            name: { type: "string", description: "Unique short name for the job" },
            schedule: { type: "string", description: "cron:... / every:... / at:..." },
            prompt: { type: "string", description: "The prompt MASTER should run on schedule" }
          },
          required: ["name", "schedule", "prompt"]
        }
      end

      def call(args)
        entry = @store.create(
          name: args.fetch("name"),
          schedule: args.fetch("schedule"),
          prompt: args.fetch("prompt")
        )
        @on_create&.call(entry)
        { created: entry[:name], schedule: entry[:schedule] }
      end
    end

    class ScheduleList < Tool
      def initialize(store)
        @store = store
      end

      def name
        "schedule_list"
      end

      def description
        "List all scheduled tasks, including whether they are enabled and when they last ran."
      end

      def parameters
        { type: "object", properties: {}, required: [] }
      end

      def call(_args)
        { jobs: @store.list }
      end
    end

    class ScheduleDelete < Tool
      def initialize(store, on_delete: nil)
        @store = store
        @on_delete = on_delete # -> (name) { ... } unregisters from the live scheduler
      end

      def name
        "schedule_delete"
      end

      def description
        "Delete a scheduled task by name."
      end

      def parameters
        {
          type: "object",
          properties: {
            name: { type: "string", description: "Name of the schedule to delete" }
          },
          required: ["name"]
        }
      end

      def call(args)
        name = args.fetch("name")
        @store.delete(name)
        @on_delete&.call(name)
        { deleted: name }
      end
    end
  end
end
