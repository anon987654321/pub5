# frozen_string_literal: true

require "digest"
require "json"
require_relative "design"

module Master
  module Face
    # One semantic contract for every MASTER surface. Browser code receives the
    # same block as MASTER_FACE_CONTRACT; Ruby consumers read it here instead
    # of growing their own copies of mode, prompt, or spatial constants.
    module Contract
      module_function

      def data(root: Master::ROOT)
        Master.tokens(root:).fetch("face_interface", {})
      end

      def prompt(root: Master::ROOT) = data(root:).fetch("prompt", {})
      def state(root: Master::ROOT) = data(root:).fetch("state", {})
      def still_modes(root: Master::ROOT)
        Array(state(root:).fetch("still_modes", ["idle"])).map(&:to_s).freeze
      end
      def still_mode?(mode, root: Master::ROOT) = still_modes(root:).include?(mode.to_s.downcase)
      def still_after_activity_ms(root: Master::ROOT)
        Integer(state(root:).fetch("still_after_activity_ms", 700)).clamp(0, 10_000)
      end
      def spatial(root: Master::ROOT) = data(root:).fetch("spatial", {})

      def prompt_measure(root: Master::ROOT)
        prompt(root:).fetch("measure_ch", Master::Design::Thresholds.measure_ideal_ch(root:))
      end

      # The plain-ASCII renderer's tunables; the terminal and the web face both read them.
      def ascii(root: Master::ROOT) = data(root:).fetch("ascii", {})

      # The prompt glyphs: :input, :continuation or :output.
      def glyph(name, root: Master::ROOT) = ascii(root:).fetch("prompt", {}).fetch(name.to_s)

      def budget(root: Master::ROOT) = spatial(root:).fetch("budget", {})
      def camera(root: Master::ROOT) = spatial(root:).fetch("camera", {})
      def layers(root: Master::ROOT)
        Array(spatial(root:).fetch("layers", [])).map(&:to_s).freeze
      end

      def mode_aliases(root: Master::ROOT)
        aliases = state(root:).fetch("mode_aliases", data(root:).fetch("mode_aliases", {}))
        (aliases || {}).transform_keys(&:to_s).transform_values(&:to_s).freeze
      end

      def prompt_max(root: Master::ROOT)
        prompt(root:).fetch("max_ch", 72)
      end

      # The Tree ksh prompt: a checkout-relative path, one wide space, and the
      # dollar — "pub5/MASTER $". No host: a line that starts with the machine's
      # name and ends in $ reads as a shell login, and the REPL is not one. A
      # path inside the checkout keeps the checkout's name and its road below;
      # a path outside falls back to the home-relative spelling. When the road
      # must be shortened it keeps the checkout, the gap and the standing leaf.
      PATH_SOFT_MAX = 24

      def shell_prompt(path: Master.repo_root, llm: nil, root: Master::ROOT)
        dir = checkout_path(path)
        dir = road_shortened(dir)
        budget = [prompt_max(root:) - 2, 1].max
        dir = dir[-budget, budget] if dir.length > budget
        name = llm.to_s.strip
        "#{dir} #{name.empty? ? "$" : "#{name}@master$"}"
      end

      # The road as the ksh prompt draws it: checkout-relative inside the
      # checkout, home-relative outside it.
      def checkout_path(path)
        repo = File.expand_path(Master.repo_root)
        dir = File.expand_path(path.to_s)
        return File.basename(repo) if dir == repo
        return "#{File.basename(repo)}/#{dir.delete_prefix("#{repo}/")}" if dir.start_with?("#{repo}/")

        home = Dir.home
        dir == home ? "~" : dir.sub(%r{\A#{Regexp.escape(home)}/}, "~/")
      end

      # Deep roads keep the checkout, the gap and the standing leaf.
      def road_shortened(dir)
        return dir unless dir.length > PATH_SOFT_MAX && dir.count("/") > 2

        segments = dir.split("/")
        "#{segments.first}/.../#{segments.last(2).join('/')}"
      end

      def user_token(root: Master::ROOT) = prompt(root:).fetch("user_token", "user")
      def master_token(root: Master::ROOT) = prompt(root:).fetch("master_token", "master")

      # The stipple dials for one mode; an unknown mode reads as idle, as the web face does.
      def stipple_profile(mode, root: Master::ROOT)
        profiles = data(root:).fetch("stipple", {}).fetch("profiles", {})
        profiles.fetch(mode.to_s) { profiles.fetch("idle") }.transform_keys(&:to_s).freeze
      end

      # What a state means in the stipple material: its membership, its force and a note.
      # An unknown mode reads as idle, as the dials do.
      def stipple_meaning(mode, root: Master::ROOT)
        face = data(root:)
        name = face.fetch("stipple_force", {}).key?(mode.to_s) ? mode.to_s : "idle"
        { "membership" => face.fetch("stipple_membership", {}).fetch(name),
          "force" => face.fetch("stipple_force", {}).fetch(name),
          "note" => face.fetch("stipple_note", {}).fetch(name) }.freeze
      end

      # The one-pixel sprite's camera-depth brightness response is shared with
      # the browser shader through this canonical contract.
      def stipple_depth_response(root: Master::ROOT)
        data(root:).fetch("stipple", {}).fetch("depth_response", {}).transform_keys(&:to_s).freeze
      end

      def modes(root: Master::ROOT)
        Array(state(root:).fetch("modes", [])).map(&:to_s).freeze
      end
    end

    # A glyph is a view of a ranked law, never a parallel list of principles.
    module LawField
      MAX_CACHE_ENTRIES = 4
      @mutex = Mutex.new
      @cache = {}

      module_function

      def config(root: Master::ROOT)
        Master.load_laws(root:).fetch("face_ascii", {})
      end

      def laws(root: Master::ROOT)
        settings = config(root:)
        glyphs = Array(settings.fetch("law_glyphs", []))
        limit = Integer(settings.fetch("max_laws", 8)).clamp(0, glyphs.size)

        with_glyphs(ranked_laws(catalog(root:)).first(limit), glyphs)
      end

      def with_glyphs(rows, glyphs)
        rows.each_with_index.map { |row, index| row.merge("glyph" => glyphs.fetch(index)) }
      end

      def ranked_laws(catalog)
        catalog.filter_map do |id, row|
          next unless row.is_a?(Hash) && row["node"]
          next if row["statement"].to_s.empty?

          {
            "id" => id.to_s,
            "node" => row.fetch("node").to_s,
            "precedence" => nil,
            "statement" => row.fetch("statement").to_s
          }
        end.each_with_index.map do |row, index|
          row.merge("precedence" => index + 1)
        end
      end

      def browser_payload(root: Master::ROOT)
        rows = laws(root:)
        settings = config(root:)

        {
          schema: 1,
          laws: rows,
          digest: Digest::SHA256.hexdigest(JSON.generate(rows)),
          toggle_key: settings.fetch("web_law_toggle_key", "l"),
          overlay_toggle_key: settings.fetch("web_toggle_key", "v"),
          enabled: settings.fetch("web_overlay", true),
        }
      end

      def catalog(root: Master::ROOT)
        root = Master.master_root(root:)
        path = File.join(root, "data", "laws.yml")
        stat = File.stat(path)
        key = [path, stat.size, stat.ino, stat.mtime.to_r]
        @mutex.synchronize do
          return @cache.fetch(key) if @cache.key?(key)

          @cache.clear if @cache.size >= MAX_CACHE_ENTRIES
          @cache[key] = Master.load_yaml(path) || {}
        end
      end
    end
  end
end
