# frozen_string_literal: true

module Master
  module Fix
    class UserSimulation
      # Scenario surface: the interaction-campaign oracle. Maps a target path
      # to campaign surfaces, renders the scenario context the model sees and
      # validates the campaign contract on first read. The defining file is
      # fix/best_of_n.rb; this re-opens its UserSimulation class.
      def scenario_context(path:)
        data = campaign
        ids = surfaces_for(path)
        return "USER SIMULATION: no campaign surface maps to this target. Do not claim user-interaction coverage." if ids.empty?

        surfaces = data.fetch("surfaces").to_h { |row| [row.fetch("id"), row] }
        faults = data.fetch("fault_modes").to_h { |row| [row.fetch("id"), row] }
        cases = data.fetch("cases").select { |row| ids.include?(row.fetch("surface_id")) }
        lines = scenario_header(ids)
        lines.concat(scenario_surface_lines(ids, surfaces))
        lines.concat(scenario_case_lines(cases, surfaces, faults))
        lines.join("\n")
      rescue StandardError => e
        publish("repair_loop:user_simulation_unavailable", path: path.to_s, reason: reason(e))
        "USER-SIMULATION BLOCKED: the campaign could not be read and validated (#{e.class}). Do not claim that scenarios were checked."
      end

      def surfaces_for(path)
        relative = relative_path(path)
        return [] unless relative

        rails_surface_ids(relative) || master_surface_ids(relative) || []
      end

      def focused_test_paths_for(surface_id)
        surface = campaign.fetch("surfaces").find { |row| row.fetch("id") == surface_id }
        Array(surface&.fetch("focused_test_paths", []))
      end

      def test_paths_for(path)
        relative = relative_path(path)
        return [] unless relative

        ids = surfaces_for(path)
        candidates = []
        candidates << relative if test_path?(relative)
        candidates.concat(matching_test_paths(relative))
        mapped = ids.flat_map { |id| focused_test_paths_for(id).first(1) }
        secondary = ids.flat_map { |id| focused_test_paths_for(id).drop(1) }
        candidates.concat(mapped).concat(secondary)
        target = File.expand_path(path.to_s, @root)
        candidates.select do |candidate|
          candidate_path = File.expand_path(File.join(@root, candidate))
          candidate_path != target && File.file?(candidate_path)
        end.uniq.first(MAX_TEST_FILES)
      end

      private

      def scenario_header(ids)
        [
          "USER-SIMULATION ORACLES",
          "These action/fault pairs guide this candidate. A scenario row is not an executed test or a passing result.",
          "The inventory runtime_status remains authoritative; NOT_RUN must not be described as passed.",
          "Relevant surfaces: #{ids.join(", ")}",
        ]
      end

      def scenario_surface_lines(ids, surfaces)
        ids.flat_map do |id|
          surface = surfaces.fetch(id)
          focused = Array(surface.fetch("focused_test_paths", []))
          lines = ["Surface #{id}; actor: #{surface.fetch("actor")}; invariant: #{surface.fetch("contract")}"]
          lines << "Focused existing tests: #{focused.join(", ")}" unless focused.empty?
          lines
        end
      end

      def scenario_case_lines(cases, surfaces, faults)
        cases.map do |row|
          surface = surfaces.fetch(row.fetch("surface_id"))
          action = surface.fetch("actions").find { |item| item.fetch("id") == row.fetch("action_id") }
          fault = faults.fetch(row.fetch("fault_mode"))
          [
            row.fetch("id"),
            "actor=#{surface.fetch("actor")}",
            "action=#{action.fetch("action")}",
            "fault=#{fault.fetch("setup")}",
            "expected=#{surface.fetch("contract")} #{fault.fetch("expected")}",
            "inventory_state=#{row.fetch("runtime_status")}",
          ].join(" | ")
        end
      end

      def rails_surface_ids(relative)
        return nil unless relative.start_with?("RAILS/")

        case relative
        when %r{\ARAILS/brgen/engines/dating/} then %w[dating]
        when %r{\ARAILS/brgen/engines/marketplace/engines/takeaway/} then %w[takeaway]
        when %r{\ARAILS/brgen/engines/marketplace/} then %w[market_discovery market_checkout]
        when %r{\ARAILS/brgen/engines/messenger/} then %w[messenger]
        when %r{\ARAILS/brgen/engines/maps/} then %w[maps_events]
        when %r{\ARAILS/brgen/engines/radio/playlist/} then %w[radio_playlist]
        when %r{\ARAILS/brgen/engines/radio/tv/} then %w[tv]
        when %r{\ARAILS/brgen/} then brgen_surfaces(relative)
        when %r{\ARAILS/amber/} then amber_surfaces(relative)
        when %r{\ARAILS/bsdports/} then %w[bsdports]
        when %r{\ARAILS/__shared/} then shared_surface_ids(relative)
        when %r{\ARAILS/test/} then test_tree_surface_ids(relative)
        end
      end

      def master_surface_ids(relative)
        case relative
        when %r{\AMASTER/web/} then master_web_surfaces(relative)
        when %r{\AMASTER/lib/fix/}, %r{\AMASTER/test/test_(?:fix|repair_loop|best_of_n|user_simulation)}
          %w[master_fix]
        when %r{\AMASTER/lib/cli/}, %r{\AMASTER/bin/}
          %w[master_cli]
        when %r{\AMASTER/lib/io/(?:web|http|sse)}
          %w[master_chat]
        when %r{\A(?:OPENBSD|STUDIO)/}
          []
        when %r{\AMASTER/checks/}
          relative.match?(%r{face|primer|page_simulation}) ? %w[master_face cross_cut] : %w[cross_cut]
        when %r{\AMASTER/}
          %w[master_fix]
        else
          %w[cross_cut]
        end
      end

      def shared_surface_ids(relative)
        relative.match?(%r{pwa|offline|service.?worker|manifest}) ? %w[pwa] : %w[cross_cut]
      end

      def test_tree_surface_ids(relative)
        relative.match?(%r{pwa|offline|stimulus}) ? %w[pwa] : %w[cross_cut]
      end

      def campaign
        return @campaign if @campaign

        parsed = JSON.parse(File.read(@campaign_path, encoding: "UTF-8"))
        validate_campaign_shape!(parsed)
        validate_campaign_surfaces!(parsed)
        validate_campaign_cases!(parsed)
        @campaign = parsed
      end

      def validate_campaign_shape!(parsed)
        surfaces = parsed.fetch("surfaces")
        faults = parsed.fetch("fault_modes")
        cases = parsed.fetch("cases")
        raise "campaign must declare 400 cases" unless parsed.fetch("case_count") == 400 && cases.size == 400
        raise "campaign must declare 20 surfaces" unless parsed.fetch("surface_count") == 20 && surfaces.size == 20
        raise "campaign must declare 20 fault modes" unless faults.size == 20
        raise "duplicate surface id" unless surfaces.map { |row| row.fetch("id") }.uniq.size == surfaces.size
        raise "duplicate fault id" unless faults.map { |row| row.fetch("id") }.uniq.size == faults.size
        raise "duplicate case id" unless cases.map { |row| row.fetch("id") }.uniq.size == cases.size
      end

      def validate_campaign_surfaces!(parsed)
        surfaces = parsed.fetch("surfaces")
        fault_ids = parsed.fetch("fault_modes").map { |row| row.fetch("id") }
        surfaces.each { |surface| validate_campaign_surface!(surface, parsed, fault_ids) }
      end

      def validate_campaign_surface!(surface, parsed, fault_ids)
        rows = parsed.fetch("cases").select { |row| row.fetch("surface_id") == surface.fetch("id") }
        actions = surface.fetch("actions")
        action_ids = actions.map { |row| row.fetch("id") }
        focused_paths = surface.fetch("focused_test_paths")
        raise "#{surface.fetch("id")} must have 20 cases" unless rows.size == 20
        raise "#{surface.fetch("id")} must have 20 actions" unless actions.size == 20
        raise "#{surface.fetch("id")} has duplicate action ids" unless action_ids.uniq.size == action_ids.size
        raise "#{surface.fetch("id")} has duplicate action text" unless actions.map { |row| row.fetch("action") }.uniq.size == actions.size
        raise "#{surface.fetch("id")} must have focused tests" if focused_paths.empty?
        validate_focused_paths!(focused_paths)
        raise "#{surface.fetch("id")} must cover all fault modes" unless rows.map { |row| row.fetch("fault_mode") }.sort == fault_ids.sort
      end

      def validate_focused_paths!(focused_paths)
        focused_paths.each do |focused_path|
          raise "focused test path must be repository-relative" if focused_path.start_with?("/")
          raise "focused test path escapes the repository" if focused_path.split("/").include?("..")
        end
      end

      def validate_campaign_cases!(parsed)
        surface_map = parsed.fetch("surfaces").to_h { |row| [row.fetch("id"), row] }
        fault_ids = parsed.fetch("fault_modes").map { |row| row.fetch("id") }
        parsed.fetch("cases").each { |row| validate_campaign_case!(row, surface_map, fault_ids) }
      end

      def validate_campaign_case!(row, surface_map, fault_ids)
        surface = surface_map[row.fetch("surface_id")]
        raise "unknown campaign surface" unless surface
        raise "unknown campaign fault" unless fault_ids.include?(row.fetch("fault_mode"))
        action_ids = surface.fetch("actions").map { |action| action.fetch("id") }
        raise "#{row.fetch("id")} references an unknown action" unless action_ids.include?(row.fetch("action_id"))
        raise "invalid runtime status" unless RUNTIME_STATES.include?(row.fetch("runtime_status"))
        return unless %w[PASS FAIL].include?(row.fetch("runtime_status"))

        raise "#{row.fetch("id")} has a runtime verdict without evidence" if row.fetch("runtime_evidence").to_s.empty?
      end

      def relative_path(path)
        expanded = File.expand_path(path.to_s, @root)
        prefix = "#{@root}/"
        return unless expanded.start_with?(prefix)

        relative = expanded.delete_prefix(prefix)
        cursor = @root
        relative.split(File::SEPARATOR).each do |component|
          cursor = File.join(cursor, component)
          return if File.symlink?(cursor)
        end

        root_real = File.realpath(@root)
        target_real = File.realpath(expanded)
        return unless target_real.start_with?("#{root_real}/")
        return unless File.file?(target_real)

        relative
      rescue SystemCallError
        nil
      end

      def brgen_surfaces(relative)
        return %w[brgen_auth cross_cut] if relative.match?(%r{session|registration|password|auth|oauth|user\.rb})
        return %w[market_discovery market_checkout] if relative.match?(%r{marketplace|listing|storefront|cart|checkout|payout|wishlist|affiliate})
        return %w[dating] if relative.match?(%r{dating|swipe|match|profile})
        return %w[messenger] if relative.match?(%r{message|conversation|inbox|messenger})
        return %w[takeaway] if relative.match?(%r{takeaway|restaurant|menu.?item|group.?order})
        return %w[maps_events] if relative.match?(%r{maps?|nearby|location|event|rsvp})
        return %w[radio_playlist] if relative.match?(%r{playlist|radio|track.?import})
        return %w[tv] if relative.match?(%r{tv|video|broadcast|watch.?time})

        %w[brgen_social]
      end

      def amber_surfaces(relative)
        return %w[amber_wardrobe] if relative.match?(%r{wardrobe|item|garment|photo|upload})
        return %w[amber_outfits] if relative.match?(%r{outfit|style|closet|declutter|wear|analytics|dressing})
        return %w[amber_social] if relative.match?(%r{post|connection|message|social|feed|follow})

        %w[amber_wardrobe]
      end

      def master_web_surfaces(relative)
        return %w[pwa] if relative.match?(%r{pwa|manifest|sw\.js|service.?worker})
        return %w[master_chat] if relative.match?(%r{chat|sse|stream|rate.?limit|message|auth})

        %w[master_face]
      end

      def test_path?(relative)
        relative.match?(%r{\A(?:MASTER|RAILS)/.*(?:_test\.rb|\.test\.mjs|_test\.mjs)\z})
      end

      def matching_test_paths(relative)
        base = File.basename(relative).sub(/\.[^.]+\z/, "")
        roots = test_roots(relative)
        patterns = [
          "**/#{base}_test.rb",
          "**/test_#{base}.rb",
          "**/#{base}.test.mjs",
          "**/#{base}_test.mjs",
        ]
        roots.flat_map do |test_root|
          patterns.flat_map do |pattern|
            Dir.glob(File.join(test_root, pattern)).map { |absolute| absolute.delete_prefix("#{@root}/") }
          end
        end.uniq.sort
      end

      def test_roots(relative)
        case relative
        when %r{\AMASTER/web/}
          [File.join(@root, "MASTER", "web", "test")]
        when %r{\AMASTER/}
          [File.join(@root, "MASTER", "test")]
        when %r{\ARAILS/__shared/}
          %w[brgen amber bsdports].map { |app| File.join(@root, "RAILS", app, "test") }
        when %r{\ARAILS/brgen/engines/}
          [File.join(@root, "RAILS", "brgen", "test")]
        when %r{\ARAILS/(brgen|amber|bsdports)/}
          [File.join(@root, "RAILS", Regexp.last_match(1), "test")]
        when %r{\ARAILS/}
          [File.join(@root, "RAILS", "test")]
        else
          []
        end
      end
    end
  end
end
