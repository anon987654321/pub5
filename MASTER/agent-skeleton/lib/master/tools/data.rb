# frozen_string_literal: true

begin
  require "polars"
rescue LoadError
  nil # optional dependency; #call degrades gracefully when missing
end

module Master
  module Tools
    # Inspect a CSV/Parquet/JSON data file via polars-ruby.
    # Deliberately read-only for now; extend with filters/aggregations when
    # MASTER starts doing real analysis.
    class DataInspect < Tool
      def name
        "data_inspect"
      end

      def description
        "Load a CSV/Parquet/JSON data file and return its shape, columns, dtypes, " \
          "a preview of rows and summary statistics."
      end

      def parameters
        {
          type: "object",
          properties: {
            path: { type: "string", description: "Path to the data file (.csv, .parquet, .json)" },
            rows: { type: "integer", description: "Number of preview rows (1-50)" }
          },
          required: ["path"]
        }
      end

      def call(args)
        unless defined?(Polars)
          return { error: "polars-ruby not installed; add `gem \"polars-ruby\"` and run bundle install" }
        end

        path = args.fetch("path")
        df = load(path)
        rows = args.fetch("rows", 5).to_i.clamp(1, 50)

        {
          shape: df.shape,
          columns: df.columns,
          dtypes: df.columns.zip(df.dtypes).map { |c, d| [c, d.to_s] },
          head: df.head(rows).to_s,
          describe: summary(df)
        }
      end

      private

      def load(path)
        case File.extname(path).downcase
        when ".csv"     then Polars.read_csv(path)
        when ".parquet" then Polars.read_parquet(path)
        when ".json"    then Polars.read_json(path)
        else raise ArgumentError, "unsupported data file type: #{path}"
        end
      end

      def summary(df)
        df.describe.to_s
      rescue StandardError
        "summary statistics unavailable for this frame"
      end
    end
  end
end
