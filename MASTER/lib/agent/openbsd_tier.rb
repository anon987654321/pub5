# frozen_string_literal: true

# bin/master openbsd-tier PATH - the admission gate's tier, made mechanical.
#
# The full manual-receipt gate is right for a behavior change and crushing
# for a comment. The principle already exists: a prose file with no native
# interface needs source review, not invented manuals. This classifier names
# the tier from the path and the diff, so an agent knows whether it is in
# the light gate or the heavy one without guessing, and a reasoned
# comment-only fix is not blocked in spirit by a gate meant for pfctl.

require "open3"

module Master
  module Agent
    module OpenbsdTier
      extend Base

      HEAVY = [
        %r{\AOPENBSD/mirror/etc/},       # cron, rc.d, relayd, nsd, pf: the host runs this
        %r{\AOPENBSD/bin/},              # executable behavior
        %r{\AOPENBSD/.*\.(sh|ksh|zsh)\z}, # install and repair scripts
        %r{\AOPENBSD/mirror/usr/},
        %r{\.conf\z},                    # pf.conf, relayd.conf, nsd.conf
        %r{\AOPENBSD/(?!.*\.(md|txt)\z)}, # anything else with behavior
      ].freeze

      class << self
        include Base

        def run(argv)
          path = argv.first
          refuse("openbsd-tier", "no PATH given", "a path inside OPENBSD/ the change touches") if path.nil?
          normalized = path.delete_prefix("/")
          normalized = File.join("OPENBSD", normalized) unless normalized.start_with?("OPENBSD/")
          unless normalized.start_with?("OPENBSD/")
            refuse("openbsd-tier", "#{path} is not in the OPENBSD tree", "a path the OPENBSD gate governs; other trees have their own lane")
          end

          heavy = HEAVY.any? { |pattern| normalized.match?(pattern) }
          comment_only = comment_only_change?(normalized)

          tier = if heavy && !comment_only
                   "heavy"
                 elsif heavy && comment_only
                   "light-with-custody"
                 else
                   "light"
                 end

          emit(
            command: "openbsd-tier",
            path: normalized,
            tier:,
            comment_only_change: comment_only,
            required: requirements(tier),
            principle: if tier == "light"
                         "a prose file with no native interface needs source review, not invented manuals"
                       else
                         "behavior on vm23 is gated by the manual receipt: measured on the host, with the rollback named"
                       end,
          )
          0
        end

        # A comment-only diff carries no behavior: every added and removed
        # line is a comment, a blank, or a fence. Judged from the diff, not
        # from hope.
        def comment_only_change?(normalized)
          out, status = Open3.capture2("git", "-C", repo_root, "diff", "HEAD", "--", normalized)
          return false unless status.success?

          changes = out.each_line.select { |l| l.start_with?("+", "-") && !l.start_with?("+++", "---") }
          return false if changes.empty?

          changes.all? do |line|
            body = line.delete_prefix("+").delete_prefix("-").strip
            body.empty? || body.start_with?("#", "//", "/*", "*", "<!--")
          end
        end

        def requirements(tier)
          case tier
          when "heavy"
            ["manual receipt measured on vm23, not asserted",
             "the rollback command, tested in the same breath",
             "sh -n on every touched script",
             "one line in the RUNBOOK if the operator-facing behavior changed"]
          when "light-with-custody"
            ["the comment-only diff stat, attached to the landing",
             "sh -n if any shell file is touched at all",
             "the note that behavior did not change: nothing on vm23 is re-run"]
          else
            ["source review of the prose diff",
             "no invented manual, no invented host state"]
          end
        end
      end
    end
  end
end
