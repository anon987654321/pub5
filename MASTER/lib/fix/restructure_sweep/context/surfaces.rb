# frozen_string_literal: true

module Master
  module Fix
    class RestructureSweep
      # Repository-surface findings on the re-opened Context, split out of
      # context.rb: retired-topology stale references, duplicated prose, route
      # helpers, config.x assignments and command surfaces.
      class Context
        def self.surface_findings(target)
          stale_reference_findings(target) + prose_findings(target) + command_surface_findings(target) + route_surface_findings(target) + config_surface_findings(target)
        end

        def self.stale_reference_findings(target)
          rows = repository_files(target).filter_map do |path|
            text = File.read(path, encoding: "UTF-8")
            matches = STALE_PATHS.select { |needle| text.include?(needle) }
            matches.empty? ? nil : [path, matches]
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.stale_reference", path:)
            nil
          end
          rows.filter_map do |path, matches|
            related = rows.select { |_other, other_matches| (matches & other_matches).any? }
                        .map(&:first).reject { |other| other == path }.first(8)
            [path, "STALE_PATH_REFERENCE", "#{matches.length} retired topology reference(s): #{matches.join(", ")}", related]
          end
        end

        def self.prose_findings(target)
          paragraphs = Hash.new { |hash, key| hash[key] = [] }
          repository_files(target).select { |path| PROSE_EXTENSIONS.include?(File.extname(path).downcase) }.each do |path|
            File.read(path, encoding: "UTF-8").split(/\n\s*\n+/).each do |block|
              next if block.lstrip.start_with?("```") || block.include?("\n```")
              normalized = block.lines.map(&:strip).reject(&:empty?).join(" ").downcase.gsub(/\s+/, " ").strip
              next if normalized.length < 120 || normalized.split.length < 20
              paragraphs[normalized] << path
            end
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.prose", path:)
          end
          paragraphs.filter_map do |_paragraph, paths|
            paths = paths.uniq
            next if paths.size < 2
            paths.map do |path|
              [path, "PROSE_DUPLICATION", "prose paragraph is duplicated across #{paths.size} files", paths.reject { |other| other == path }.first(8)]
            end
          end.flatten(1)
        end

        def self.route_surface_findings(target)
          repository_files(target).select { |path| File.basename(path) == "routes.rb" }.filter_map do |path|
            text = File.read(path, encoding: "UTF-8")
            helpers = text.scan(/\bas:\s*:([a-z][a-z0-9_]*)/i).flatten
            duplicates = helpers.tally.select { |_name, count| count > 1 }.keys
            next if duplicates.empty?

            [path, "ROUTE_SURFACE_DUPLICATION", "route helper(s) declared more than once: #{duplicates.join(", ")}", []]
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.routes", path:)
            nil
          end
        end

        def self.config_surface_findings(target)
          repository_files(target).filter_map do |path|
            relative = relative_static(path, target)
            next unless relative.split("/").include?("config") && CONFIG_EXTENSIONS.include?(File.extname(path).downcase)

            text = File.read(path, encoding: "UTF-8")
            keys = text.scan(/^\s*config\.x\.([A-Za-z0-9_]+)\s*=/).flatten
            duplicates = keys.tally.select { |_name, count| count > 1 }.keys
            next if duplicates.empty?

            [path, "CONFIG_SURFACE_DUPLICATION", "config.x setting(s) assigned more than once: #{duplicates.join(", ")}", []]
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.config", path:)
            nil
          end
        end

        def self.command_surface_findings(target)
          signatures = repository_files(target).filter_map { |path| command_signature(path, target) }
          signatures.group_by { |_path, commands| commands }.values
            .select { |group| group.size > 1 }.flat_map do |group|
              group.map do |path, commands|
                [path, "COMMAND_SURFACE_DUPLICATION", "command surface #{commands.join(", ")} is duplicated across #{group.size} executables", group.map(&:first).reject { |other| other == path }.first(8)]
              end
            end
        end

        # A command surface is the switch labels and COMMANDS declarations of
        # one executable file under bin/ or tools/, so identical surfaces across
        # separate executables become one duplication finding per file.
        def self.command_signature(path, target)
          relative = relative_static(path, target)
          ext = File.extname(path).downcase
          root = relative.split("/").first
          return unless COMMAND_EXTENSIONS.include?(ext) && (COMMAND_ROOTS.include?(root) || relative.include?("/bin/"))

          text = File.read(path, encoding: "UTF-8")
          commands = []
          text.scan(/^\s*when\s+["\x27]([a-z][a-z0-9_:-]*)["\x27]/i) { |match| commands << match.first.downcase }
          text.scan(/\bCOMMANDS\s*=\s*%i\[([^\]]+)\]/) { |match| commands.concat(match.first.scan(/[a-z][a-z0-9_:-]*/i).map(&:downcase)) }
          commands = commands.uniq.sort
          return if commands.empty?

          [path, commands]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "restructure.commands", path:)
          nil
        end

        private_class_method :surface_findings, :stale_reference_findings, :prose_findings
        private_class_method :route_surface_findings, :config_surface_findings, :command_surface_findings, :command_signature
      end
    end
  end
end
