# frozen_string_literal: true

require "faraday"
require "sqlite3"

module Master
  class VectorMemoryError < StandardError; end

  # Embeds text via a local Ollama server (POST /api/embeddings).
  # Pull an embedding model once:  ollama pull nomic-embed-text
  # Swap this class for transformers.rb or a hosted API — the interface is
  # a single method: embed(text) -> Array<Float>.
  class OllamaEmbedder
    def initialize(url: ENV["MASTER_OLLAMA_URL"] || "http://localhost:11434", model: "nomic-embed-text")
      @model = model
      @conn = Faraday.new(url: url) do |f|
        f.options.timeout = 30
        f.options.open_timeout = 5
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.adapter :net_http
      end
    end

    def embed(text)
      # request :json middleware encodes the hash and sets the content-type.
      resp = @conn.post("api/embeddings", { model: @model, prompt: text.to_s })
      raise VectorMemoryError, "embedder HTTP #{resp.status}" unless resp.status == 200

      embedding = resp.body["embedding"]
      raise VectorMemoryError, "embedder returned no embedding" unless embedding.is_a?(Array) && !embedding.empty?

      embedding
    end
  end

  # Long-term semantic memory: notes embedded by an Embedder, stored as
  # float32 blobs in SQLite, searched by brute-force cosine similarity.
  # Works everywhere with zero extra dependencies. At larger scale, swap the
  # storage for sqlite-vec or Postgres + pgvector (via the `neighbor` gem) —
  # the add/search interface stays identical.
  class VectorMemory
    def initialize(path: "master.db", embedder:)
      @embedder = embedder
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = false
      @db.execute("PRAGMA journal_mode = WAL")
      @db.execute("PRAGMA busy_timeout = 5000")
      create_tables
    end

    # Store a note; returns { id:, dim: }.
    def add(text, thread_id: "default")
      vector = @embedder.embed(text)
      dim = existing_dim

      if dim && dim != vector.size
        raise VectorMemoryError,
              "embedding dimension mismatch: store has #{dim}, embedder returned #{vector.size}"
      end

      @db.execute(
        "INSERT INTO vectors (thread_id, text, vector, dim) VALUES (?, ?, ?, ?)",
        [thread_id, text.to_s, vector.pack("e*"), vector.size]
      )
      { id: @db.last_insert_row_id, dim: vector.size }
    end

    # k most similar notes; optionally scoped to one thread.
    def search(query, k: 4, thread_id: nil)
      qvec = @embedder.embed(query)
      rows = if thread_id
               @db.execute("SELECT text, thread_id, vector FROM vectors WHERE thread_id = ?", [thread_id])
             else
               @db.execute("SELECT text, thread_id, vector FROM vectors")
             end

      rows.map { |text, tid, blob| { text: text, thread_id: tid, score: cosine(qvec, blob.unpack("e*")) } }
          .sort_by { |h| -h[:score] }
          .first(k)
    end

    private

    def existing_dim
      @db.execute("SELECT dim FROM vectors LIMIT 1").first&.first
    end

    def cosine(a, b)
      dot = a.zip(b).sum { |x, y| x * y }
      na = Math.sqrt(a.sum { |x| x * x })
      nb = Math.sqrt(b.sum { |x| x * x })
      return 0.0 if na.zero? || nb.zero?

      dot / (na * nb)
    end

    def create_tables
      @db.execute <<~SQL
        CREATE TABLE IF NOT EXISTS vectors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          thread_id TEXT NOT NULL,
          text TEXT NOT NULL,
          vector BLOB NOT NULL,
          dim INTEGER NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      SQL
    end
  end
end
