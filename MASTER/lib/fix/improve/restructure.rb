# frozen_string_literal: true

require "set"
require_relative "../tree"

module Master
  module Fix
    module Improve
      # The defragmentation drive: turn TreeSprawl signals into restructure
      # proposals that respect the path contracts. A proposal is only emitted
      # when the target path is owned by the repository itself (PATH_OWNERSHIP
      # governs who may move what), so elevation never drags a contracted path
      # out from under a test that asserts it.
      class Restructure
        # A merge is contract-safe when the only references are requires that
        # move with the file. This drive therefore proposes, and lets
        # restructure_sweep's proof machinery (syntax, rails_proof, master_proof)
        # verify an accepted proposal before anything is applied.
        Proposal = Struct.new(:kind, :from, :to, :reason, keyword_init: true)

        MAX_PROPOSALS = 6
        TINY_LINES = 24

        def initialize(root:)
          @root = File.expand_path(root)
        end

        def proposals(files:, limit: MAX_PROPOSALS)
          scope = files.map { |path| File.expand_path(path, @root) }.to_set
          return [] if scope.empty?

          evidence = Tree.new(root: @root).sprawl
          tiny = evidence.fetch(:tiny_files, []).map { |path| File.expand_path(path, @root) }
          tiny.select! { |path| scope.include?(path) && path.end_with?(".rb") }
          singles = evidence.fetch(:single_file_dirs, []).map { |dir| File.expand_path(dir, @root) }
          list = []
          tiny.each do |path|
            break if limit && list.size >= limit
            target = merge_target_for(path)
            next unless target && scope.include?(target)

            list << Proposal.new(
              kind: :merge, from: path, to: target,
              reason: "#{path.sub("#{@root}/", "")} is a small neighboring component of #{target.sub("#{@root}/", "")}; verify shared ownership and caller contracts before merging"
            )
          end
          singles.each do |dir|
            break if limit && list.size >= limit
            member = scope.find { |path| File.dirname(path) == dir }
            next unless member && File.file?(member)
            destination = File.join(File.dirname(dir), File.basename(member))
            next if File.exist?(destination)

            list << Proposal.new(
              kind: :flatten, from: member, to: destination,
              reason: "#{dir.sub("#{@root}/", "")} holds one tracked direct file; flatten only if its namespace and path convey no useful contract"
            )
          end
          list
        end

        private

        def merge_target_for(path)
          lines = File.foreach(path).count
          return unless lines < TINY_LINES

          parent = File.dirname(File.dirname(path))
          stem = File.basename(File.dirname(path))
          candidate = File.join(parent, "#{stem}.rb")
          return unless File.file?(candidate)

          candidate
        end
      end
    end
  end
end
