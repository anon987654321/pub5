# frozen_string_literal: true

module Master
  module Ground
    # Answers whether an automated writer must leave a path alone. The
    # sacred-path list retired (operator decree 2026-11-09); what remains is
    # Soul.preserved_asset?, which always refuses, and a path that escapes the
    # root. Git history records how a person changed anything else.
    class Immutability
      # MASTER_SACRED_WRITES=allowed lifts the guards that are not preserved
      # assets, per run, so the switch is visible in the run env. It never
      # lifts a preserved asset.
      def self.writes_allowed?
        ENV["MASTER_SACRED_WRITES"].to_s.strip.casecmp("allowed").zero?
      end

      # Fails closed: a preserved-asset check that raises refuses the path.
      def self.preserved?(path, root:)
        Master::Soul.preserved_asset?(path, root:)
      rescue StandardError
        true
      end

      def self.blocked?(path, root: Master::ROOT)
        new(root:).blocked?(path)
      end

      def initialize(root:)
        @root = File.expand_path(root)
      end

      def blocked?(relative_or_absolute)
        return true if self.class.preserved?(relative_or_absolute, root: @root)
        return false if self.class.writes_allowed?

        escapes_root?(relative_or_absolute)
      end

      private

      def escapes_root?(path)
        full = File.expand_path(path.to_s, @root)
        !(full == @root || full.start_with?(@root + File::SEPARATOR))
      rescue ArgumentError
        true
      end
    end
  end
end
