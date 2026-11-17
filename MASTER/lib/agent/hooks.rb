# frozen_string_literal: true

# Git hooks that install themselves.
#
# The pre-commit gate in .githooks/ judges every landing, but for months it
# judged nothing here: core.hooksPath was never set on the clones made for
# agent work, and a hook that never fires is a constitution that only exists
# in the abstract. Git runs nothing on clone, so the tier does the next best
# thing: the first bin/master agent invocation in a checkout sets
# core.hooksPath to .githooks if it is unset, and `bin/master hooks status`
# reports the wiring plainly. Idempotent, quiet when already wired.

require "json"
require "open3"

module Master
  module Agent
    module Hooks
      HOOKS_DIR = ".githooks"

      class << self
        def run(argv)
          action = argv.first.to_s
          case action
          when "install" then install!
          when "status" then status
          when "ensure" then install!
          else
            puts "usage: bin/master hooks install|status"
            exit(64)
          end
        end

        def ensure_installed(root:)
          return if installed?(root)

          hooks = File.join(root, HOOKS_DIR)
          unless File.directory?(hooks)
            warn "hooks: no #{HOOKS_DIR}/ in #{root}; landing gate stays unwired (NOT_RUN)"
            return
          end

          install!(root:, quiet: false)
        rescue StandardError
          # A checkout without git must still scan; the gate stays unwired and
          # selfcheck reports it. Silence here is not silence in the gate.
          nil
        end

        def installed?(root)
          output = git(root, "config", "--get", "core.hooksPath")
          output && !output.strip.empty?
        end

        def install!(root: Dir.pwd, quiet: true)
          hooks = File.join(root, HOOKS_DIR)
          unless File.directory?(hooks)
            warn "hooks: no #{HOOKS_DIR}/ in #{root}; nothing to install (NOT_RUN)"
            exit(1)
          end
          git!(root, "config", "core.hooksPath", HOOKS_DIR)
          return if quiet

          puts "hooks: core.hooksPath set to #{HOOKS_DIR} " \
               "(pre-commit, commit-msg, post-commit, pre-push now fire)"
        end

        def status
          root = Dir.pwd
          wired = installed?(root)
          dir = File.join(root, HOOKS_DIR)
          hooks = Dir.exist?(dir) ? Dir.children(dir).sort : []
          puts JSON.pretty_generate(
            hooks_path: wired ? git(root, "config", "--get", "core.hooksPath").strip : nil,
            wired:,
            hooks_present: hooks,
            note: wired ? "the landing gate fires on every commit" :
                          "unwired: every landing runs ungated; run bin/master hooks install"
          )
          exit(wired ? 0 : 1)
        end

        private

        def git(root, *args)
          out, status = Open3.capture2("git", "-C", root, *args)
          status.success? ? out : nil
        end

        def git!(root, *args)
          system("git", "-C", root, *args) || abort("hooks: git #{args.join(' ')} failed")
        end
      end
    end
  end
end
