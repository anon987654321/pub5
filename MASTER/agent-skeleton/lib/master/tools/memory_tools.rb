# frozen_string_literal: true

module Master
  module Tools
    # remember / recall: long-term semantic memory backed by VectorMemory
    # (embeddings via Ollama by default). Failures surface as tool errors
    # the model can see (e.g. embedder offline).
    class Remember < Tool
      def initialize(vectors)
        @vectors = vectors
      end

      def name
        "remember"
      end

      def description
        "Store a note in long-term semantic memory so it can be recalled later by meaning."
      end

      def parameters
        {
          type: "object",
          properties: {
            text: { type: "string", description: "The note to remember (self-contained, factual)" }
          },
          required: ["text"]
        }
      end

      def call(args)
        @vectors.add(args.fetch("text"))
      end
    end

    class Recall < Tool
      def initialize(vectors)
        @vectors = vectors
      end

      def name
        "recall"
      end

      def description
        "Search long-term semantic memory for the notes most relevant to a query."
      end

      def parameters
        {
          type: "object",
          properties: {
            query: { type: "string", description: "What to search for" },
            k: { type: "integer", description: "Max notes to return" }
          },
          required: ["query"]
        }
      end

      def call(args)
        notes = @vectors.search(args.fetch("query"), k: args.fetch("k", 4).to_i.clamp(1, 20))
        { notes: notes.map { |n| { text: n[:text], score: n[:score].round(3) } } }
      end
    end
  end
end
