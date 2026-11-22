# frozen_string_literal: true

require_relative "../../trace/self_evolution_trigger"

module Master
  module CLI
    module CommandRegistry
      module_function

      # Directories the boot tree never descends into: dependencies, build output
      # and runtime state.
      SKIP_SEGS = %w[
        .git .master vendor tmp var node_modules .bundle coverage log dist knowledge
        runtime .venv renders storage quarantine .cache
      ].freeze

      COMMIT_USAGE = "usage: /commit <path>... --confirm - name what goes in. Other sessions " \
                     "edit this checkout, so a commit that sweeps up every change is refused."

      # /commit — stage and commit the named paths, and only those, with a
      # model-written message. The checkout is shared by several sessions, so
      # `git add -u` would publish another session's half-finished work under
      # this one's message; the path list is the scope, and git enforces it
      # with `commit -- <paths>`. Paths are repository-relative ("MASTER/lib",
      # the tree-contract convention), so every git call runs at the checkout's
      # top level, resolved from the runtime directory itself: git resolves
      # pathspecs against its -C directory, and a runtime root (MASTER/) turned
      # "MASTER/lib" into MASTER/MASTER/lib, matched nothing, and answered
      # "nothing to commit" for a dirty tree.
      def dispatch_commit(agent, root, ctx: nil)
        paths = arg_for(ctx).split(/\s+/).reject(&:empty?)
        return COMMIT_USAGE if paths.empty?

        repo = git_toplevel(root)
        evolution = Master::Trace::SelfEvolutionTrigger.new(root:).call
        changed, = Master::Io::Exec.capture2e("git", "-C", repo, "status", "--porcelain", "--", *paths)
        return "commit: nothing to commit in #{paths.join(' ')}" if changed.strip.empty?

        diff, = Master::Io::Exec.capture2e("git", "-C", repo, "diff", "HEAD", "--stat", "--", *paths)
        prompt = "Write a concise git commit message (1 line, imperative mood) for:\n#{diff}\n#{changed}"
        message = agent.ask_once(prompt).to_s.strip.lines.first.to_s.strip
        return "commit: no message came back, so nothing was committed" if message.empty?

        [evolution, commit_named(repo, message:, paths:)].reject(&:empty?).join("\n")
      end

      # The checkout the named paths are relative to. The runtime directory is
      # MASTER/ inside a larger checkout, so the top level — not the runtime
      # directory — is the only directory that answers repository-relative
      # pathspecs. A caller that already passes a repository root (the focused
      # tests, a worktree checkout) resolves to itself.
      def git_toplevel(root)
        top, = Master::Io::Exec.capture2e("git", "-C", root, "rev-parse", "--show-toplevel")
        top = top.to_s.strip
        top.start_with?("/") && File.directory?(top) ? top : File.expand_path(root)
      end

      # GitOperations#commit stages and commits the named paths and nothing else, through
      # git!, where a sacred path is refused: the message is a model's.
      def commit_named(root, message:, paths:)
        Master::Io::GitOperations.new(root).commit(message, paths:).to_s.strip
      rescue RuntimeError, ArgumentError => e
        "commit: #{e.message}"
      end

      # The tree the session prints on first boot.
      def dispatch_tree(root, ctx: nil)
        arg = arg_for(ctx)
        cfg = (Master.load_laws(root:) || {}).dig("paths", "tree") || {}
        depth = arg.to_i.positive? ? arg.to_i : (cfg["max_depth"] || 2)
        cap = cfg["max_lines"] || 200
        tree_lines = []
        walk_tree(root, 1, depth:, cap:, tree_lines:)
        tree_lines.join("\n")
      end

      def walk_tree(dir, level, depth:, cap:, tree_lines:)
        return if level > depth || tree_lines.size >= cap

        Dir.children(dir).sort.each do |name|
          break if tree_lines.size >= cap
          next if name.start_with?(".") || SKIP_SEGS.include?(name)

          path = File.join(dir, name)
          tree_lines << "#{" " * (level - 1)}#{name}#{File.directory?(path) ? "/" : ""}"
          walk_tree(path, level + 1, depth:, cap:, tree_lines:) if File.directory?(path)
        end
      rescue Errno::EACCES, Errno::ENOENT => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.walk_tree")
        nil
      end
    end
  end
end
