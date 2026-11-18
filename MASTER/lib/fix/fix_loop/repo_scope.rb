# frozen_string_literal: true

require "pathname"
require_relative "../commit_message"

module Master
  module Fix
    class FixLoop

      # /fix runs from MASTER's directory, and its git sees only MASTER: a repair to a RAILS or
      # OPENBSD file was applied, counted, and never committed. The committer also asks the
      # repository root for changes beside MASTER, names them relative to MASTER (../RAILS/...),
      # and commits through the repository root whenever a commit holds one.
      module RepoScope
        def changed_everywhere
          inside = Array(@git.changed_paths)
          return inside unless repo_git

          own = "#{repo_prefix}/"
          inside + Array(repo_git.changed_paths).reject { |path| path.start_with?(own) }.map { |path| "../#{path}" }
        end

        # Every /fix commit passes CommitMessage first: a message that breaks data/commit_format.yml raises
        # before anything is staged.
        def commit_scoped(message, paths:)
          @lease_guard&.call
          CommitMessage.check!(message)
          return @git.commit(message, paths:) unless repo_git && paths.any? { |path| path.start_with?("../") }

          repo_git.commit(message, paths: paths.map { |path| repo_relative(path) })
        end

        private

        def repo_root = Master::REPO_ROOT

        def repo_git
          return @repo_git if defined?(@repo_git)

          @repo_git = beside_repo? ? Master::Io::GitOperations.new(repo_root) : nil
        end

        # Only a workspace physically contained by this checkout may borrow its
        # Git writer. A lexical prefix is insufficient: /work/pub5-old is not
        # inside /work/pub5, and symlinked workspace roots must not redirect the
        # repository writer into a different checkout.
        def beside_repo?
          return false unless @root && File.directory?(@root) && File.directory?(repo_root)

          workspace = File.realpath(@root)
          repository = File.realpath(repo_root)
          workspace.start_with?("#{repository}#{File::SEPARATOR}")
        rescue SystemCallError
          false
        end

        def repo_prefix
          workspace = File.realpath(@root)
          repository = File.realpath(repo_root)
          raise ArgumentError, "fix workspace is outside its repository" unless
            workspace.start_with?("#{repository}#{File::SEPARATOR}")

          Pathname.new(workspace).relative_path_from(repository).to_s
        end

        def repo_relative(path)
          repository = File.realpath(repo_root)
          workspace = File.realpath(@root)
          absolute = File.expand_path(path.to_s, workspace)
          unless workspace.start_with?("#{repository}#{File::SEPARATOR}") &&
                 absolute.start_with?("#{repository}#{File::SEPARATOR}")
            raise ArgumentError, "fix delivery path is outside its repository"
          end

          Pathname.new(absolute).relative_path_from(repository).to_s
        end
      end
    end
  end
end
