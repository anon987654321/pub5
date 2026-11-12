# frozen_string_literal: true

require "sqlite3"

module Master
  class ScheduleError < StandardError; end

  # Persistent schedule definitions in SQLite. The Rufus::Scheduler runtime
  # (see scheduler.rb) loads these on boot; jobs survive MASTER restarts.
  #
  # Schedule strings are prefixed so one column can express all kinds:
  #   "cron:0 9 * * *"        cron expression
  #   "every:30m"             fixed interval
  #   "at:2026-12-24 09:00"   one-shot at a time
  class ScheduleStore
    def initialize(path: "master.db")
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = false
      @db.execute("PRAGMA journal_mode = WAL")
      @db.execute("PRAGMA busy_timeout = 5000")
      create_tables
    end

    def create(name:, schedule:, prompt:, thread_id: "scheduler")
      raise ScheduleError, "schedule must match cron:/every:/at: prefix" unless
        schedule.to_s =~ /\A(cron|every|at):.+/

      @db.execute(
        "INSERT INTO schedules (name, schedule, prompt, thread_id) VALUES (?, ?, ?, ?)",
        [name.to_s, schedule.to_s, prompt.to_s, thread_id.to_s]
      )
      { name: name.to_s, schedule: schedule.to_s, prompt: prompt.to_s, thread_id: thread_id.to_s }
    rescue SQLite3::ConstraintException
      raise ScheduleError, "schedule name already taken: #{name}"
    end

    # Array of hashes with symbol keys.
    def list
      @db.execute("SELECT id, name, schedule, prompt, thread_id, enabled, last_run_at, last_result " \
                  "FROM schedules ORDER BY id").map do |id, name, schedule, prompt, tid, enabled, last_at, last_res|
        { id: id, name: name, schedule: schedule, prompt: prompt, thread_id: tid,
          enabled: enabled == 1, last_run_at: last_at, last_result: last_res }
      end
    end

    def delete(name)
      @db.execute("DELETE FROM schedules WHERE name = ?", [name.to_s])
      self
    end

    def set_enabled(name, enabled)
      @db.execute("UPDATE schedules SET enabled = ? WHERE name = ?", [enabled ? 1 : 0, name.to_s])
      self
    end

    def mark_run(id, result, max_chars: 2000)
      result = result.to_s
      result = result[0, max_chars] + "...[truncated]" if result.length > max_chars
      @db.execute("UPDATE schedules SET last_run_at = datetime('now'), last_result = ? WHERE id = ?",
                  [result, id])
      self
    end

    private

    def create_tables
      @db.execute <<~SQL
        CREATE TABLE IF NOT EXISTS schedules (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          schedule TEXT NOT NULL,
          prompt TEXT NOT NULL,
          thread_id TEXT NOT NULL DEFAULT 'scheduler',
          enabled INTEGER NOT NULL DEFAULT 1,
          last_run_at TEXT,
          last_result TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      SQL
    end
  end
end
