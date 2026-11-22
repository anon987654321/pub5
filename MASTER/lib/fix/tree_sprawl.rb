# frozen_string_literal: true

module Master
  module Fix
    # Structural signals for a tracked tree. These are measurements, not a
    # mandate to flatten protected boundaries or optimise file count at any cost.
    class TreeSprawl
      TINY_BYTES = 200
      DEEP = 5
      WIDE = 28
      MAX_CONCEPT_DEPTH = 3
      ROOT_FILE_LIMIT = 18
      IMPORTANT_CONCEPTS = %w[core fix law runtime soul].freeze
      # Trees that hold one directory per application rather than one library.
      # The owner of a concept in these is the application, not the fleet.
      FLEET_TREES = %w[RAILS].freeze
      # Repeated framework entrypoints and standard Rails templates do not
      # represent a domain concept scattered across owners.
      #
      # The Rails half of this list matters more now that a fleet tree counts
      # each application as its own owner: `application_record`, `current`,
      # `cable`, `importmap` and their neighbours are files every Rails app is
      # generated with, so counting owners would report the generator rather
      # than the architecture. Domain nouns shared across apps (comment, order,
      # message, review) are deliberately absent -- those are the finding.
      GENERIC_CONCEPT_STEMS = %w[
        .rubocop Gemfile README Rakefile application application_controller base base_controller
        config create.turbo_stream create.turbo_stream.html database development edit.html engine
        environment Gemfile.lock helper home_controller index index.html manifest master new.html
        pwa_controller production rails readme routes schema seeds show.html storage test_helper version
        application_reflex _card.html _form.html _live_search_results.html
        .keep application_cable application_helper application_job application_mailer
        application_record application_resource application_system_test_case account_round_trip_test
        assets brakeman cable cable_schema cache cache_schema channel connection
        content_security_policy current filter_parameter_logging importmap
        importmap_external_hosts_test importmap_external_hosts job_concurrency_test
        queue queue_schema recurring service-worker update.turbo_stream
      ].freeze
      UGLY_NAME_PATTERN = /(?:\A__|_{2,}|_(?:helper|utils|old)\z)/
      SIGNALS = %i[
        single_file_dirs tiny_files deep_dirs wide_dirs name_twins
        ugly_names concept_scatter depth_tax root_clutter
      ].freeze

      def initialize(files:, directories:, sizes:, root_prefix: ".")
        @files = files
        @directories = directories
        @sizes = sizes
        @root_prefix = root_prefix.to_s
      end

      def to_h = SIGNALS.to_h { |signal| [signal, public_send(signal)] }

      def single_file_dirs
        @directories.select { |dir| dir.files == 1 && target_path(dir.path) != "." }.map(&:path)
      end

      def tiny_files = @files.select { |path| @sizes.fetch(path) <= TINY_BYTES }

      def deep_dirs = @directories.select { |dir| dir.depth > DEEP }.map(&:path)

      def wide_dirs = @directories.select { |dir| dir.files > WIDE }.map(&:path)

      # host.rb and host_helper.rb: a concept split without a reason.
      def name_twins
        @files.group_by { |path| File.dirname(path) }.values.flat_map { |paths| twins_among(paths) }
      end

      # Flag path segments, not merely file extensions: __shared/, *_helper.rb,
      # *_utils.rb and *_old.rb are all names a human should review.
      def ugly_names
        @files.select do |path|
          path.split("/").any? do |segment|
            stem = File.basename(segment, File.extname(segment))
            next false if conventional_rails_helper?(path, stem)

            UGLY_NAME_PATTERN.match?(stem)
          end
        end
      end

      # lib/<owner>/ is the meaningful top-level boundary for Ruby concepts;
      # other trees use their first directory. Generic file entrypoints are
      # excluded so repeated index.rb or application.rb files are not noise.
      #
      # Only source counts. A stem repeated across apps is a concept when an
      # application named an idea in code; it is the generator when the repeats
      # are `config/cable.yml`, `public/icon-192.png`, a dotfile or a
      # timestamped migration. Those share a stem with their siblings because
      # Rails writes them, and each app receiving one is the framework working.
      def concept_scatter
        @files.reject { |path| generated_or_static?(path) }
              .group_by { |path| File.basename(path, File.extname(path)) }
              .filter_map do |stem, paths|
          next if stem.length < 5 || GENERIC_CONCEPT_STEMS.include?(stem)

          owners = paths.map { |path| concept_owner(path) }.uniq
          [stem, paths.sort] if owners.size >= 3
        end
      end

      # Important concepts buried beyond the third path segment are hard to
      # discover and usually indicate that ownership has drifted too deep.
      def depth_tax
        @files.select do |path|
          target_path(path).split("/").each_with_index.any? do |segment, index|
            next false unless index + 1 > MAX_CONCEPT_DEPTH

            stem = File.basename(segment, File.extname(segment))
            IMPORTANT_CONCEPTS.include?(stem)
          end
        end
      end

      # Root files are counted at the measured target's boundary, not always
      # at the checkout root (a scan of MASTER/lib has its own root).
      def root_clutter
        root_files = @files.select { |path| File.dirname(target_path(path)) == "." }
        root_files.size > ROOT_FILE_LIMIT ? root_files : []
      end

      private

      # Rails and its toolchain write these into every application. They carry a
      # shared stem because each app was generated with one, not because an idea
      # was spread across owners, so they are not evidence of scatter.
      #
      # The split is by location, not by extension. `config/*.yml` is framework
      # configuration, but `data/personas.yml` and `RAILS/brgen/domains.yml` are
      # declarations of an idea and stay in the count; `.rb` files under config/
      # stay too, which is how security_headers -- genuinely implemented as an
      # initializer, a web middleware and a check -- is still reported.
      GENERATED_DIRS = %w[
        db public script bin vendor log tmp storage
        test spec app/views/layouts app/mailers
      ].freeze
      FRAMEWORK_CONFIG_EXTS = %w[.yml .yaml].freeze
      STATIC_EXTS = %w[.png .jpg .jpeg .gif .svg .ico .txt .json .lock].freeze

      def generated_or_static?(path)
        parts = target_path(path).split("/")
        ext = File.extname(path)
        return true if File.basename(path).start_with?(".")
        return true if STATIC_EXTS.include?(ext)
        return true if FRAMEWORK_CONFIG_EXTS.include?(ext) && parts.each_index.any? { |i| parts[i] == "config" }

        parts.each_index.any? { |index| prefix_matches?(parts[0..index].join("/"), GENERATED_DIRS) }
      end

      def prefix_matches?(prefix, dirs)
        dirs.any? { |dir| prefix == dir || prefix.end_with?("/#{dir}") }
      end

      # Rails deliberately names helper files with the _helper suffix, and
      # test_helper.rb is a conventional test entrypoint. They are not
      # structural naming debt. Keep __ prefixes and repeated underscores visible.
      def conventional_rails_helper?(path, stem)
        return true if stem == "test_helper"
        path_parts = path.split("/")
        return true if (path_parts.include?("test") || path_parts.include?("spec")) && stem.end_with?("_helper")

        path_parts.each_cons(2).any? { |left, right| left == "app" && right == "helpers" } &&
          stem.end_with?("_helper")
      end

      # A fleet is one directory per application. `lib/<owner>/` is the boundary
      # inside a single tree, but RAILS/ holds brgen, amber, bsdports and the rest
      # side by side, each already its own application with its own Gemfile and
      # deploy root. Counting `parts.first` made every one of them the owner
      # "RAILS", so three apps disagreeing about dispatch_policy measured as one
      # owner and the scatter signal could never fire where it matters most.
      def concept_owner(path)
        parts = target_path(path).split("/")
        lib_index = parts.index("lib")
        owner = if lib_index && parts.size > lib_index + 2
                  parts.first(lib_index + 2).join("/")
                else
                  parts.first
                end
        fleet_owner(parts, owner) || owner
      end

      # The application directory of a fleet tree: the segment after the tree
      # name, and only when that segment is not itself the concept. Files that
      # sit directly in the tree keep the tree as their owner.
      def fleet_owner(parts, owner)
        return unless FLEET_TREES.include?(parts.first)
        return unless parts.size > 2

        candidate = parts.first(2).join("/")
        candidate unless candidate == owner && parts.size == 3
      end

      def target_path(path)
        return path if @root_prefix.empty? || @root_prefix == "."
        return "." if path == @root_prefix

        path.delete_prefix("#{@root_prefix}/")
      end

      def twins_among(paths)
        by_stem = paths.to_h { |path| [File.basename(path, File.extname(path)), path] }
        by_stem.keys.product(by_stem.keys).filter_map do |stem, other|
          [by_stem[stem], by_stem[other]] if other.start_with?("#{stem}_")
        end
      end
    end
  end
end
