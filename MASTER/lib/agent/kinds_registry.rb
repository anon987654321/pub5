# frozen_string_literal: true

# bin/master kinds [check] - exemptions as kinds, not hardcoded paths.
#
# Every catalogue path_exclude and every registry exemption is checked
# against the live tree: a path exemption whose subject no longer exists is
# the exact shape that re-armed NO_PUTS on its own exempted file after a
# rename. The registry makes the subject a fact that can be tested instead of
# a string that can rot.

require "yaml"

module Master
  module Agent
    module KindsRegistry
      extend Base

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          action = "check" if action.empty?
          case action
          when "check" then check
          when "list" then list
          else
            puts "usage: bin/master kinds check|list"
            exit(64)
          end
        end

        def registry_path
          @registry_path ||= data_path("law_kinds.yml")
        end

        def registry
          @registry ||= File.file?(registry_path) ? load_yaml(registry_path).fetch("kinds", []) : []
        end

        def list
          emit(
            command: "kinds list",
            registry: registry_path,
            kinds: registry.map do |kind|
              {
                id: kind["id"],
                subjects: kind["subjects"],
                exempt_laws: (kind["exemptions"] || {}).keys,
                description: kind["description"].to_s.strip,
              }
            end
          )
          0
        end

        def check
          breaches = []
          registry.each do |kind|
            (kind["subjects"] || []).each do |glob|
              full = File.join(repo_root, glob)
              matches = Dir.glob(full)
              next unless matches.empty?

              breaches << { kind: kind["id"], subject: glob, problem: "no live path matches this glob" }
            end
          end

          unowned = []
          stale = []
          all_paths = Dir.glob(File.join(repo_root, "**", "*"))
          catalogue_entries.each do |id, entry|
            next unless entry.is_a?(Hash)

            Array(entry["path_exclude"]).each do |pattern|
              next unless pattern.to_s.match?(%r{/})

              # The exclusion must name something that exists, or something a
              # kind owns. A live exclusion nobody owns is one rename away
              # from re-arming on its own subject; a dead one is a retirement
              # candidate the prune report collects.
              owned = registry.any? { |kind| (kind["exemptions"] || {}).key?(id) }
              alive = begin
                all_paths.any? { |p| p.match?(Regexp.new(pattern)) }
              rescue Regexp::Error => e
                warn "kinds: #{id} path_exclude does not compile: #{e.message}"
                false
              end
              next if owned

              bucket = alive ? unowned : stale
              bucket << { law: id, subject: pattern }
            end
          end

          emit(
            command: "kinds check",
            kinds: registry.size,
            breaches:,
            unowned_exclusions: unowned,
            stale_exclusions: stale,
            verdict: if breaches.empty?
                       "every kind subject is live; #{unowned.size} unowned, #{stale.size} stale exclusions"
                     else
                       "kind drift found"
                     end,
          )
          breaches.empty? ? 0 : 1
        end
      end
    end
  end
end
