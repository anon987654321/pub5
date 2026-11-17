# frozen_string_literal: true

module Master
  module Fix
    class RestructureSweep
      # Reverse-reference evidence on the re-opened Context, split out of
      # context.rb: the lines elsewhere that name the file, the production-only
      # subset, the small files that require it in full, and the parsing helpers
      # those sections share.
      class Context
        private

        def production_reference_section
          hits = production_references.flat_map do |path, lines|
            lines.map { |number, text| "#{relative(path)}:#{number}: #{text.strip[0, 160]}" }
          end
          return if hits.empty?

          "Production references:\n#{hits.first(REFERENCE_LINES).join("\n")}"
        end

        def reference_section
          hits = references.flat_map do |path, lines|
            lines.map { |number, text| "#{relative(path)}:#{number}: #{text.strip[0, 160]}" }
          end
          return if hits.empty?

          "Lines elsewhere that name it:\n#{hits.first(REFERENCE_LINES).join("\n")}"
        end

        def requirer_section
          requirers = references.keys.select { |path| File.read(path, encoding: "UTF-8").match?(require_pattern) }
                                .select { |path| File.foreach(path, encoding: "UTF-8").count <= SMALL }.first(REQUIRERS)
          return if requirers.empty?

          requirers.map { |path| "Requires it, in full, #{relative(path)}:\n#{numbered(path)}" }.join("\n\n")
        end

        # { path => [[line_number, text]] } for files that name the stem or a constant.
        def production_references
          @production_references ||= Context.reference_files(@root)
            .reject { |path| path == @path || test_path?(path) || PROSE_EXTENSIONS.include?(File.extname(path).downcase) }
            .to_h do |path|
              [path, File.foreach(path, encoding: "UTF-8").with_index(1).select { |text, _n| text.match?(needle) }.map(&:reverse)]
            rescue ArgumentError
              [path, []]
            end.reject { |_path, lines| lines.empty? }
        end

        def references
          @references ||= Context.reference_files(@root).reject { |path| path == @path }.to_h do |path|
            [path, File.foreach(path, encoding: "UTF-8").with_index(1).select { |text, _n| text.match?(needle) }.map(&:reverse)]
          rescue ArgumentError
            [path, []]
          end.reject { |_path, lines| lines.empty? }
        end

        def needle
          @needle ||= Regexp.union([require_pattern, *constants.map { |name| /\b#{name}\b/ }])
        end

        def require_pattern
          stem = Regexp.escape(File.basename(@path, ".*"))
          /require(?:_relative)?\s*\(?\s*["'][^"']*\b#{stem}["']/
        end

        def constants
          File.read(@path, encoding: "UTF-8").scan(/^\s*(?:class|module)\s+([A-Z]\w+)/).flatten.uniq - Restructure.namespaces(@tree)
        end

        def test_path?(path)
          path.split("/").any? { |part| %w[test spec fixtures].include?(part) }
        end
      end
    end
  end
end
