# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      def dispatch_documents(_root, agent, ctx: nil)
        return "documents0 at master0: local operator only" if Fiber[:master_visitor]
        return "documents0 at master0: no active vision model" unless agent

        args = Shellwords.split(arg_for(ctx))
        action = args.shift.to_s.downcase
        return help_text("documents") if action.empty? || action == "help"
        return "documents0 at master0: usage: /documents analyze [directory] [--max-pages N]" unless action == "analyze"

        directory = args.first&.start_with?("--") ? "photos" : (args.shift || "photos")
        limit = Master::Io::DocumentArchive::DEFAULT_MAX_PAGES
        until args.empty?
          option = args.shift
          case option
          when "--max-pages"
            value = args.shift
            return "documents0 at master0: --max-pages needs an integer" unless value&.match?(/\A\d+\z/)
            limit = value.to_i
          else
            return "documents0 at master0: unexpected argument #{option.inspect}"
          end
        end

        result = Master::Io::DocumentArchive.new(agent:).analyze(directory:, max_pages: limit)
        result.ok? ? result.value!.fetch(:rendered) : result.message.to_s
      rescue ArgumentError => e
        "documents0 at master0: invalid arguments - #{e.message}"
      rescue StandardError => e
        "documents0 at master0: FAILED #{e.class}: #{e.message}"
      end
    end
  end
end
