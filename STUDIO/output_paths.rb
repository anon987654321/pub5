# frozen_string_literal: true

# Keep media deliverables outside the checkout. Producers and Postpro share
# this path contract instead of guessing output locations.
module Studio
  module OutputPaths
    FALLBACK_DATA_HOME = File.expand_path("~/Downloads").freeze
    REPOSITORY_ROOT = File.realpath(File.expand_path("..", __dir__)).freeze

    module_function

    def data_home
      configured = ENV.fetch("XDG_DATA_HOME", "").to_s
      return fallback_data_home if configured.empty?
      return fallback_data_home unless configured.start_with?(File::SEPARATOR)

      candidate = canonical_path(configured)
      return fallback_data_home if inside_repository?(candidate)

      candidate
    end

    # Even the fallback must be safe: Downloads can itself be a symlink into
    # the checkout. Refuse that rare configuration rather than writing renders
    # into the repository under the guise of a fallback.
    def fallback_data_home(path = FALLBACK_DATA_HOME)
      if inside_repository?(path)
        raise ArgumentError, "fallback data home resolves inside the checkout: #{path}"
      end

      path
    end

    def canonical_path(path)
      expanded = File.expand_path(path)
      cursor = expanded
      missing = []
      until File.exist?(cursor) || File.symlink?(cursor)
        parent = File.dirname(cursor)
        break if parent == cursor

        missing.unshift(File.basename(cursor))
        cursor = parent
      end
      File.join(File.realpath(cursor), *missing)
    rescue SystemCallError
      expanded
    end

    # Operator directive, 2026-11-07: every render — photo, video or audio —
    # goes straight into the data home with no kind or date subfolders.
    # Filenames keep their millisecond stamps, so same-second collisions are
    # the only naming concern, and the kind-level environment override stays
    # the one knob that can move a render lane elsewhere.
    def flat_directory(override:)
      configured = override ? ENV.fetch(override, "").to_s : ""
      unless configured.empty?
        candidate = canonical_path(configured)
        if inside_repository?(candidate)
          raise ArgumentError, "#{override} resolves inside the checkout: #{configured}"
        end
        return candidate
      end

      data_home
    end

    def render_directory
      flat_directory(override: "POSTPRO_OUTPUT_DIR")
    end

    def dilla_render_directory(at: nil)
      base = flat_directory(override: "DILLA_OUTPUT_DIR")
      # An operator-pinned DILLA_OUTPUT_DIR is the exact directory, not a root
      # to scope further. The default data home keeps one folder per UTC day,
      # which is the granularity MASTER's output-path contract queries with
      # (RAILS/test/studio_contract_test.rb pins the date conversion).
      return base if at.nil? || !ENV.fetch("DILLA_OUTPUT_DIR", "").to_s.empty?

      File.join(base, "dilla-renders", at.utc.strftime("%Y-%m-%d"))
    end

    # The reference crate is input material, not a render, so it keeps its
    # one subfolder under the data home.
    def reference_root
      File.join(data_home, "dilla-references")
    end

    def inside_repository?(path)
      canonical = canonical_path(path)
      canonical == REPOSITORY_ROOT ||
        canonical.start_with?("#{REPOSITORY_ROOT}#{File::SEPARATOR}")
    end
  end
end
