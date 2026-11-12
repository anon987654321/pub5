# frozen_string_literal: true

require "sqlite3"
require "json"

module Master
  # Durable conversation memory. Kept deliberately simple:
  #   - one messages table keyed by thread_id
  #   - history() rebuilds OpenAI-format message hashes
  # Next step: add a vector table (sqlite-vec, or Postgres + pgvector via the
  # `neighbor` gem) and a search_relevant(query) method for semantic recall.
  class Memory
    def initialize(path: "master.db")
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = false
      create_tables
    end

    def append(thread_id, role:, content:, payload: nil)
      @db.execute(
        "INSERT INTO messages (thread_id, role, content, payload) VALUES (?, ?, ?, ?)",
        [thread_id, role, content, payload && JSON.generate(payload)]
      )
      self
    end

    # Returns chat history in OpenAI message format (string keys), oldest first.
    def history(thread_id, limit: 200)
      rows = @db.execute(
        "SELECT role, content, payload FROM messages " \
        "WHERE thread_id = ? ORDER BY id DESC LIMIT ?",
        [thread_id, limit]
      ).reverse

      rows.filter_map do |role, content, payload|
        if payload
          JSON.parse(payload)
        else
          { "role" => role, "content" => content.to_s }
        end
      end
    end

    def reset(thread_id)
      @db.execute("DELETE FROM messages WHERE thread_id = ?", [thread_id])
      self
    end

    private

    def create_tables
      @db.execute <<~SQL
        CREATE TABLE IF NOT EXISTS messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          thread_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT,
          payload TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      SQL
      @db.execute(
        "CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages (thread_id, id)"
      )
    end
  end
end
