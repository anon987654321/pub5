# frozen_string_literal: true

require "fileutils"

module Master
  module Fix
    class ScreenshotSweep
      # The operator's review set: one phone-width shot per page, at
      # RAILS/screenshot_<n>_<app>_<page>.png (tracked), replaced whole by
      # each sweep that captured something. The leading number is the page's
      # position in the sweep, so the set reads in the order it was captured and
      # a reader can name a shot in one word. Old sweep folders are pruned to the
      # newest KEEP_SWEEPS; renders are replaceable, and eleven of them had grown
      # to 414 MB by 2026-11-04.
      class ReviewSet
        WIDTH = Integer(ENV.fetch("MASTER_SCREENSHOT_REVIEW_WIDTH", "390"))
        KEEP_SWEEPS = Integer(ENV.fetch("MASTER_SCREENSHOT_KEEP_SWEEPS", "2"))
        PATTERN = "screenshot_*.png"
        # What a review shot and a sweep folder are named; nothing else is
        # deleted here (NEVER_BATCH_DELETE: one named, confirmed path per call).
        # Matches both the numbered name and any pre-numbering name a stale sweep
        # left, so a re-publish clears the old set rather than doubling it.
        SHOT_NAME = /\Ascreenshot_[A-Za-z0-9_-]+\.png\z/
        SWEEP_NAME = /\Asweep-\d{8}T\d{6}Z\z/

        def initialize(root:, sweep_dir:)
          @rails = File.join(root, "RAILS")
          @sweep_dir = sweep_dir
        end

        # Copies each page's WIDTH shot out of the sweep; returns how many. The
        # old set goes first, always: a review must never read a shot this sweep
        # did not render. A sweep that captured nothing therefore leaves no
        # review set rather than last run's pictures under this run's name.
        def publish!(rows)
          picks = []
          rows.each do |row|
            pick = pick(row, picks.size + 1)
            picks << pick if pick
          end
          Dir.glob(File.join(@rails, PATTERN)).each do |old|
            remove_shot(old)
          end
          picks.each { |source, name| FileUtils.cp(source, File.join(@rails, name)) }
          picks.size
        end

        # Deletes all but the newest KEEP_SWEEPS sweep folders beside this one.
        def prune!
          parent = File.dirname(@sweep_dir)
          sweeps = Dir.children(parent).select { |name| sweep_folder?(parent, name) }.sort
          stale = sweeps[0...-KEEP_SWEEPS] || []
          stale.each do |name|
            path = File.join(parent, name)
            FileUtils.rm_rf(path) if sweep_folder?(parent, name) && path != @sweep_dir
          end
          stale.size
        end

        private

        # A review shot: directly in RAILS/, named screenshot_<page>.png.
        def remove_shot(path)
          confirmed = File.dirname(path) == @rails && File.basename(path).match?(SHOT_NAME) && File.file?(path)
          File.delete(path) if confirmed
        end

        def sweep_folder?(parent, name)
          name.match?(SWEEP_NAME) && File.directory?(File.join(parent, name))
        end

        def pick(row, number)
          shot = row.shots[WIDTH.to_s] || row.shots[WIDTH]
          return unless shot

          source = File.join(@sweep_dir, shot)
          return unless File.file?(source)

          [source, "screenshot_#{number}_#{row.app}_#{page_name(row, shot)}.png"]
        end

        # The page's slug for the shot name. An app's own front page is
        # "frontpage" rather than the host slug a root route otherwise produces
        # ("root" on loopback, "brgen_no" on the brgen apex); a vertical's root
        # keeps its host, so dating.brgen.no's front page stays distinct.
        def page_name(row, shot)
          slug = File.basename(File.dirname(shot))
          slug == "root" || slug == "#{row.app}_no" ? "frontpage" : slug
        end
      end
    end
  end
end
