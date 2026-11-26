# frozen_string_literal: true

require "prism"
require "yaml"
require_relative "../fix/openbsd_manual_preflight"

module Master::Core
  # Constitution — the single check. Every Effect the agent proposes folds
  # through the rules here before the World performs anything. This is where the
  # old council, scan, judge, biases, veto, evidence, sharp_edges, and the Guard
  # all live now: not as subsystems, but as rules over effects. One `admit`.
  #
  # A rule watches a verb and returns no finding, Revise, Block, or Request.
  # admit runs the full applicable chain before honoring requests: any Block
  # wins, and revisions after a pending request fail closed and require re-admission.
  class Constitution
    Law = Data.define(:id, :verbs, :judge) do
      def watches?(verb) = verbs.include?(verb)
    end

    REPO_TREES = MasterPaths::TREES
    FORBIDDEN_BASENAMES = %w[summary.md analysis.md report.md todo.md notes.md changelog.md].freeze
    TWO_HATS_LINES = 200
    SCOPE_TREES = 4
    SCOPE_SECONDS = 1_800
    FEAT_RX = /\b(feat|fix|add|ship|implement)\b/i
    REFACTOR_RX = /\b(refactor|cleanup|clean up|restructure|rewrite)\b/i

    # verify is the scanner, supplied rather than required: the spine reaches
    # nothing in lib/. It takes (path:, content:) and answers what the write
    # introduces, so the design law judges a write on the way in, like every
    # other rule here, instead of waiting for someone to run a scan.
    # sandbox is the exec counterpart of verify, and injected for the same reason:
    # the spine reaches nothing in lib/, so the hardened shell policy is handed in
    # rather than required. It takes (argv) and answers a deny reason or nil.
    #
    # Without it, the only thing standing between the model and the machine was
    # safe_exec_rule's veto regex over the joined argv. Io::Shell has consulted
    # Ground::Policy::Sandbox — an adversarial corpus covering dangerous rm in any
    # flag order, fork bombs, curl-piped-to-shell, device truncation — since that
    # check was wired in, but the Fold does not exec through Io::Shell. It execs
    # through World. So the hardened check was live for the tool path and absent
    # from the constitutional one, which is the path that actually runs unattended.
    def self.load(data_dir:, workspace_root: nil, verify: nil, sandbox: nil, probe: nil, capabilities: Capabilities.for(:fix))
      master_root = File.expand_path(File.dirname(data_dir))
      # One reader of laws.yml: the boot accessor, which also keeps foreign
      # scanner roots quiet when they carry no constitution of their own.
      rules_data = Master.load_laws(root: master_root)
      workspace_root = File.expand_path(workspace_root || master_root)
      rules = default_rules(rules_data, workspace_root:, probe:)
      rules += [scan_clean_rule(verify)] if verify
      rules += [sandboxed_exec_rule(sandbox)] if sandbox
      new(laws: rules, capabilities:)
    end

    def initialize(laws:, capabilities: Capabilities.for(:fix))
      @laws = laws
      @capabilities = capabilities
    end

    attr_reader :capabilities

    # Run every applicable law before returning Allow, Block, or deferred Request.
    def admit(effect, memory)
      allowed = begin
        @capabilities.allow?(effect.capability)
      rescue StandardError => e
        return Verdict::Block.new(
          reason: "capability evaluation failed: #{e.class}",
          by: :capability_evaluator_error,
        )
      end
      unless allowed == true
        return Verdict::Block.new(
          reason: "capability refused: #{effect.capability}",
          by: :capability,
        )
      end

      requests = []
      @laws.each do |law|
        watching = begin
          law.watches?(effect.verb)
        rescue StandardError => e
          return Verdict::Block.new(
            reason: "law applicability check failed: #{law.id} (#{e.class})",
            by: :law_evaluator_error,
          )
        end
        unless watching == true || watching == false
          return Verdict::Block.new(
            reason: "law applicability check returned invalid result: #{law.id} (#{watching.class})",
            by: :law_evaluator_error,
          )
        end
        next unless watching

        answer = begin
          law.judge.call(effect, memory)
        rescue StandardError => e
          return Verdict::Block.new(
            reason: "law evaluation failed: #{law.id} (#{e.class})",
            by: :law_evaluator_error,
          )
        end

        case answer
        in Verdict::Block => b then return b
        # A request is not a safety verdict. Keep checking every later law so a
        # yes cannot approve an effect that a subsequent law would block.
        in Verdict::Request => request
          unless request.effect == effect
            return Verdict::Block.new(
              reason: "law changed the effect while requesting approval",
              by: :law_evaluator_error,
            )
          end
          requests << request
        in Verdict::Revise(effect: revised)
          if requests.any?
            return Verdict::Block.new(
              reason: "effect revised after an approval request; re-admission is required",
              by: :law_order,
            )
          end
          effect = revised
        else
          # nil is the established "no finding" value for individual predicates.
          # Any other unrecognized return is a broken evaluator, not approval.
          next if answer.nil?

          return Verdict::Block.new(
            reason: "law evaluator returned invalid verdict: #{law.id} (#{answer.class})",
            by: :law_evaluator_error,
          )
        end
      end
      return Verdict::Allow.new(effect:) if requests.empty?

      if requests.one?
        request = requests.first
        return Verdict::Request.new(effect:, prompt: request.prompt, reason: request.reason, by: request.by)
      end

      prompts = requests.map { |request| "#{request.by}: #{request.prompt}" }.join("\n")
      reasons = requests.map { |request| "#{request.by}: #{request.reason}" }.join("; ")
      Verdict::Request.new(
        effect:,
        prompt: "This effect needs approval for all checks:\n#{prompts}",
        reason: reasons,
        by: :multiple_constitutional_checks,
      )
    end

    # The rules. Each is a few lines because the dangerous thing is expressed as
    # a predicate, not prose. Safety rules Block; hygiene rules Revise.
    def self.default_rules(data, workspace_root: nil, probe: nil)
      veto = (data["veto_pattern_config"] || {}).to_h { |n, s| [n, safe_rx(n, s["detect"])] }

      [
        no_secret_rule(veto),
        configuration_invariant_rule(workspace_root:),
        ruby_parses_rule,
        structured_exec_rule,
        read_only_probe_rule(probe),
        safe_exec_rule(veto),
        batch_delete_rule,
        forbidden_file_rule,
        scope_creep_rule,
        evidence_for_done_rule,
        git_commit_evidence_rule,
        git_commit_scope_rule,
        git_stage_rule,
        two_hats_rule,
        council_for_done_rule,
        ideation_before_write_rule,
        new_path_rule,
        openbsd_manual_preflight_rule,
        effect_reversibility_rule,
      ]
    end

    # Configuration content is judged by its schema and constitutional invariants
    # on every Fold write. Whether the Fold may write a path at all is World's
    # separate question, answered by Constitution::Paths.write_refusal.
    # The guard is shared with lib/fix/write_guard.rb and sits outside the
    # fold's seven-file concept budget (data/spine.yml core_files), so it is
    # resolved through the shared loader rather than required from lib/.
    def self.configuration_invariant_rule(workspace_root:)
      Law.new(id: :configuration_invariant, verbs: %i[write], judge: lambda { |effect, _memory|
        reason = Master::ConfigurationGuard.validate(
          path: effect.args[:path],
          content: effect.args[:content].to_s,
          root: workspace_root,
        )
        next nil unless reason

        Verdict::Block.new(reason:, by: :configuration_invariant)
      })
    end

    # No credential ever reaches disk, a transcript, a command or commit history.
    def self.no_secret_rule(veto)
      Law.new(id: :no_secret, verbs: %i[write note exec git browser], judge: lambda { |effect, _memory|
        pattern = veto["secrets"]
        next Verdict::Block.new(
          reason: "veto_pattern_config.secrets missing or invalid - effects are unjudgeable for secrets",
          by: :no_secret,
        ) unless pattern.respond_to?(:match?)

        body = [effect.args[:content], effect.args[:text], effect.args[:message], effect.args[:url],
                Array(effect.args[:argv]).map(&:to_s)].flatten.compact.join("\n")
        next nil unless body.match?(pattern)

        Verdict::Block.new(reason: "secret in effect content", by: :no_secret)
      })
    end

    # Every Ruby file the agent writes must parse. The check that was missing
    # while 109 lib files rotted; here it cannot be skipped.
    def self.ruby_parses_rule
      Law.new(id: :ruby_parses, verbs: %i[write], judge: lambda { |effect, _memory|
        next nil unless effect.args[:path].to_s.end_with?(".rb")

        err = ruby_syntax_error(effect.args[:content].to_s)
        err ? Verdict::Block.new(reason: err, by: :ruby_parses) : nil
      })
    end

    # A write may carry the debt already in the file it replaces; it may not add
    # to it. Blocking on the whole file would refuse the first repair of any file
    # that already breaks a rule.
    def self.scan_clean_rule(verify)
      Law.new(id: :scan_clean, verbs: %i[write], judge: lambda { |effect, _memory|
        blocking = verify.call(path: effect.args[:path], content: effect.args[:content].to_s)
        next nil if blocking.empty?

        Verdict::Block.new(reason: "write introduces #{blocking.join("; ")}", by: :scan_clean)
      })
    end

    # The hardened shell policy, applied to the constitutional exec path.
    #
    # Blocks on a denial only. The policy answers :deny, :ask or :allow, and :ask
    # is what it returns for anything it does not recognise — which is most real
    # commands — so treating :ask as a refusal would stop the fold running its own
    # tests. Io::Shell made the same call for the same reason; this keeps the two
    # checks saying the same thing rather than inventing a second opinion.
    # The sandbox answers one of three things, and the third is new:
    #
    #   nil                 nothing to say; later rules decide
    #   "reason"            deny, as before
    #   { ask: "reason" }   a person decides
    #
    # A Hash rather than another String, because a deny reason and an ask reason
    # would otherwise be the same value meaning opposite things. A sandbox that
    # only ever returns a String or nil keeps exactly its old behaviour.
    def self.sandboxed_exec_rule(sandbox)
      Law.new(id: :sandboxed_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
        answer = sandbox.call(Array(effect.args[:argv]).map(&:to_s)) or next nil

        if answer.is_a?(Hash) && answer[:ask]
          command = Array(effect.args[:argv]).join(" ")
          next Verdict::Request.new(
            effect:,
            prompt: "run `#{command}`? (#{answer[:ask]})",
            reason: answer[:ask].to_s,
            by: :sandboxed_exec,
          )
        end

        Verdict::Block.new(reason: "sandbox denied: #{answer}", by: :sandboxed_exec)
      })
    end

    # A read-only diagnostic has its own capability and exact allowlist. It is
    # not an alternate spelling of exec: a missing policy blocks it.
    def self.read_only_probe_rule(probe)
      Law.new(id: :read_only_probe, verbs: %i[probe], judge: lambda { |effect, _memory|
        next Verdict::Block.new(reason: "read-only probe policy unavailable", by: :read_only_probe) unless probe

        reason = probe.call(Array(effect.args[:argv]).map(&:to_s))
        next nil if reason.nil?

        Verdict::Block.new(reason: "read-only probe refused: #{reason}", by: :read_only_probe)
      })
    end

    # RTFM_FIRST is a capability-boundary check, not prompt-only conduct.
    # Fold writes and exec effects consume the same receipt as the tool Shell.
    def self.openbsd_manual_preflight_rule
      Law.new(id: :openbsd_manual_preflight, verbs: %i[write exec], judge: lambda { |effect, _memory|
        reason = if effect.verb == :write
                   Master::Fix::OpenBSDManualPreflight.refusal_for_path(path: effect.args[:path])
                 else
                   Master::Fix::OpenBSDManualPreflight.refusal_for_command(
                     command: Array(effect.args[:argv]).map(&:to_s).join(" ")
                   )
                 end
        reason ? Verdict::Block.new(reason: "RTFM_FIRST blocked: #{reason}", by: :openbsd_manual_preflight) : nil
      })
    end

    # Unsafe shell never executes.
    def self.safe_exec_rule(veto)
      Law.new(id: :safe_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
        command = Array(effect.args[:argv]).join(" ")
        next nil unless veto["unsafe_calls"] && command.match?(veto["unsafe_calls"])

        Verdict::Block.new(reason: "unsafe command", by: :safe_exec)
      })
    end

    # One path at a time. Added after a 16-file untracked wipe; the operator
    # sentence is the Fold's next exec, not a batch argv.
    def self.batch_delete_reason(argv)
      argv = Array(argv).map(&:to_s)
      git_command, git_args = git_command_parts(argv)
      if git_command == "clean" && !git_clean_dry_run?(git_args)
        return "git clean refused: it can erase ignored screenshots, private LoRA sources, datasets and trained models"
      end
      if git_command == "reset" && git_args.include?("--hard")
        return "git reset --hard refused: it can discard retained screenshot changes"
      end

      preserved = preserved_asset_delete_reason(argv, git_command:, git_args:)
      return preserved if preserved
      return "batch delete refused: git clean without a pathspec" if git_clean_all?(argv)

      paths = delete_operands(argv)
      return if paths.size <= 1

      "batch delete refused: #{paths.size} paths - one path at a time"
    end

    # Five rules below share one shape: work out a reason from the effect, and
    # block under the rule's own id when there is one. The block returns nil to
    # pass.
    def self.reason_rule(id, verbs, &reason)
      Law.new(id:, verbs:, judge: lambda { |effect, memory|
        text = reason.call(effect, memory)
        text ? Verdict::Block.new(reason: text, by: id) : nil
      })
    end

    def self.batch_delete_rule
      reason_rule(:batch_delete, %i[exec]) { |effect, _memory| batch_delete_reason(effect.args[:argv]) }
    end

    def self.forbidden_file_reason(path)
      name = File.basename(path.to_s).downcase
      return unless FORBIDDEN_BASENAMES.include?(name)

      "forbidden file: #{name} - deliver code, not a sidecar markdown"
    end

    def self.forbidden_file_rule
      reason_rule(:forbidden_file, %i[write]) { |effect, _memory| forbidden_file_reason(effect.args[:path]) }
    end

    def self.scope_creep_reason(path, proof)
      tree = path.to_s.split("/").find { |part| REPO_TREES.include?(part) }
      trees = Array(proof.scope[:trees]) | [tree].compact
      return "scope creep: #{trees.size} trees (#{trees.join(", ")})" if trees.size >= SCOPE_TREES

      elapsed = proof.scope[:elapsed_s].to_f
      return unless elapsed >= SCOPE_SECONDS && tree && proof.scope[:trees].any? && !proof.scope[:trees].include?(tree)

      "scope creep: #{(elapsed / 60).to_i} min tangent into #{tree}"
    end

    def self.scope_creep_rule
      reason_rule(:scope_creep, %i[write]) { |effect, memory| scope_creep_reason(effect.args[:path], memory.proof) }
    end

    def self.two_hats_reason(message, lines)
      return if lines.to_i <= TWO_HATS_LINES

      text = message.to_s
      return unless text.match?(FEAT_RX) && text.match?(REFACTOR_RX)

      "two hats: #{lines} lines mix a feature/fix with a refactor"
    end

    def self.two_hats_rule
      reason_rule(:two_hats, %i[git]) do |effect, memory|
        next nil unless effect.args[:operation].to_s.to_sym == :commit

        two_hats_reason(effect.args[:message], memory.proof.scope[:write_lines])
      end
    end

    def self.git_command_parts(argv)
      return [nil, []] unless File.basename(argv.first.to_s) == "git"

      index = 1
      while (option = argv[index]) && option.start_with?("-")
        index += %w[-C -c --git-dir --work-tree].include?(option) ? 2 : 1
      end
      [argv[index], argv.drop(index + 1)]
    end

    def self.git_clean_dry_run?(args)
      Array(args).any? do |argument|
        argument == "--dry-run" ||
          (argument.start_with?("-") && !argument.start_with?("--") &&
           argument.delete_prefix("-").include?("n"))
      end
    end

    def self.git_clean_all?(argv)
      command, args = git_command_parts(argv)
      command == "clean" && !git_clean_dry_run?(args) && operands_after_flags(args).empty?
    end

    # A path-specific delete/restore is refused when it names a preserved
    # asset or a directory containing one. Git clean is handled above because
    # its default scope includes ignored local media that Git cannot enumerate.
    def self.preserved_asset_delete_reason(argv, git_command: nil, git_args: nil)
      argv = Array(argv).map(&:to_s)
      executable = File.basename(argv.first.to_s)
      paths = if executable == "rm" || executable == "mv"
                operands_after_flags(argv.drop(1))
              elsif executable == "git"
                args = git_args || git_command_parts(argv).last
                case git_command || git_command_parts(argv).first
                when "rm", "mv"
                  operands_after_flags(args)
                when "restore"
                  next_paths = args.index("--")
                  next_paths ? args.drop(next_paths + 1) : operands_after_flags(args)
                when "checkout"
                  marker = args.index("--")
                  marker ? args.drop(marker + 1) : []
                else
                  []
                end
              else
                []
              end

      paths.each do |path|
        [Dir.pwd, Master::REPO_ROOT].uniq.each do |base|
          target = File.expand_path(path, base)
          if Master::Soul.preserved_assets_under?(target, root: Master::REPO_ROOT)
            return "preserved project asset refused: #{target}"
          end
        end
      end
      nil
    rescue StandardError
      "preserved project asset check failed; refusing destructive command"
    end

    def self.delete_operands(argv)
      return [] if argv.empty?

      cmd = File.basename(argv.first)
      rest = argv.drop(1)
      case cmd
      when "rm"
        operands_after_flags(rest)
      when "git"
        return [] unless rest[0] == "rm"

        operands_after_flags(rest.drop(1))
      else
        []
      end
    end

    def self.operands_after_flags(args)
      past = false
      args.reject do |arg|
        next false if past
        if arg == "--"
          past = true
          next true
        end
        arg.start_with?("-")
      end
    end

    def self.structured_exec_rule
      Law.new(id: :structured_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
        argv = effect.args[:argv]
        next nil if argv.is_a?(Array) && argv.all? { |arg| arg.is_a?(String) } && !argv.empty?

        Verdict::Block.new(reason: "exec requires argv: [String, ...]", by: :structured_exec)
      })
    end

    # The agent may not declare success without evidence (no completion theater).
    # A fold that only read is answering, not claiming a change; see
    # Proof#answered_from_reads?.
    def self.evidence_for_done_rule
      Law.new(id: :evidence_for_done, verbs: %i[done], judge: lambda { |_effect, memory|
        next nil if memory.proof.proved? || memory.proof.answered_from_reads?

        Verdict::Block.new(reason: "no passing evidence on record", by: :evidence_for_done)
      })
    end

    def self.git_commit_evidence_rule
      Law.new(id: :git_commit_evidence, verbs: %i[git], judge: lambda { |effect, memory|
        next nil unless effect.args[:operation].to_s.to_sym == :commit
        next nil if memory.proof.proved?

        Verdict::Block.new(reason: "cannot commit before evidence threshold", by: :git_commit_evidence)
      })
    end

    # A fold may commit only paths it successfully wrote itself. This lets a
    # verified, path-scoped checkpoint land without a second prompt while keeping
    # other sessions' and the operator's work outside its authority.
    def self.git_commit_scope_rule
      Law.new(id: :git_commit_scope, verbs: %i[git], judge: lambda { |effect, memory|
        next nil unless effect.args[:operation].to_s.to_sym == :commit

        paths = Array(effect.args[:paths]).map(&:to_s).map(&:strip).reject(&:empty?).uniq
        next Verdict::Block.new(reason: "commit must name its paths; the index is shared", by: :git_commit_scope) if paths.empty?

        written = Array(memory.proof.scope[:write_paths])
        outside = paths - written
        unless outside.empty?
          next Verdict::Block.new(
            reason: "commit may include only paths written by this fold; not owned here: #{outside.first(5).join(", ")}",
            by: :git_commit_scope,
          )
        end

        expected_hashes = memory.proof.repository_commit_hashes(paths)
        unless expected_hashes
          next Verdict::Block.new(
            reason: "commit refused: task-owned file contents changed or have no verified delivery receipt",
            by: :git_commit_scope,
          )
        end

        revised = Effect.new(verb: :git, args: effect.args.merge(expected_hashes:))
        Verdict::Revise.new(effect: revised, by: :git_commit_scope)
      })
    end

    # Staging is part of one path-scoped commit, never a separate fold action.
    # The World stages only exact new files and preserves the shared index.
    def self.git_stage_rule
      Law.new(id: :git_stage_disabled, verbs: %i[git], judge: lambda { |effect, _memory|
        next nil unless effect.args[:operation].to_s.to_sym == :stage

        Verdict::Block.new(
          reason: "git stage is not a separate action; use one evidence-backed path-scoped commit",
          by: :git_stage_disabled,
        )
      })
    end

    # High-risk goals require an in-process council critique before done.
    def self.council_for_done_rule
      Law.new(id: :council_for_done, verbs: %i[done], judge: lambda { |_effect, memory|
        next nil unless memory.proof.council_required?
        next nil if memory.proof.council_cleared?

        Verdict::Block.new(reason: "run critique (council tribunal) before done on high-risk goals", by: :council_for_done)
      })
    end

    # Medium+ goals must carry ideation notes seeded before the first write.
    def self.ideation_before_write_rule
      Law.new(id: :ideation_before_write, verbs: %i[write], judge: lambda { |_effect, memory|
        next nil if memory.proof.ideation_satisfied?

        Verdict::Block.new(reason: "ideation not complete - approaches/chosen must be in memory", by: :ideation_before_write)
      })
    end

    # Medium+ unread path: read it first (edit) or ask (new file). The January
    # delete-and-recreate incident wrote over approved work without a read.
    def self.new_path_reason(path, proof)
      return unless %i[medium high critical].include?(proof.risk)
      return if Array(proof.scope[:read_paths]).include?(path.to_s)
      return if proof.scope[:asked]

      "unread path #{path} - read it or ask before writing"
    end

    def self.new_path_rule
      reason_rule(:new_path_ask, %i[write]) { |effect, memory| new_path_reason(effect.args[:path], memory.proof) }
    end

    # Reversibility is derived from the actual Effect, not accepted as a model
    # assertion. Shared-index staging needs a person; a commit is separately
    # gated by proof and same-fold path ownership. An operation without a World
    # handler is blocked rather than "approved" into a dead end.
    # A compensating command is separately re-admitted and approved after failure.
    def self.effect_reversibility_rule
      Law.new(id: :effect_reversibility, verbs: VERBS, judge: lambda { |effect, memory|
        contract = effect.reversibility
        case contract.kind
        when :approval_required
          if effect.verb == :git && effect.args[:operation].to_s.to_sym == :commit &&
             effect.args[:expected_hashes].is_a?(Hash) && memory.proof.proved?
            next nil
          end

          operation = effect.verb == :git ? " git #{effect.args[:operation]}" : " #{effect.verb}"
          scope = contract.scope.to_s.empty? ? "" : " on #{contract.scope}"
          Verdict::Request.new(
            effect:,
            prompt: "Approve#{operation}#{scope}? #{contract.reason}.",
            reason: contract.reason,
            by: :effect_reversibility,
          )
        when :unknown
          Verdict::Block.new(reason: contract.reason, by: :effect_reversibility)
        end
      })
    end

    # Prism parses in-process and returns every syntax error, so no child
    # process, PATH lookup or timeout stands between the fold and its next write.
    def self.ruby_syntax_error(content)
      Prism.parse(content).errors.first&.message
    end

    # A veto pattern that does not compile would leave its rule with nothing to
    # match, so every secret or unsafe command would pass. Refuse to build the
    # constitution instead.
    def self.safe_rx(name, pattern)
      Regexp.new(pattern, Regexp::MULTILINE)
    rescue RegexpError, TypeError => e
      raise ArgumentError, "veto pattern #{name} is invalid: #{e.message}"
    end

    # The surface is load and admit. The rest are rule
    # factories `default_rules` calls and nothing else does, verified against
    # lib/, test/, tools/, bin/ and web/.
    #
    # Declared rather than merely true: `private` marks a position in the
    # instance-method stream and class methods never enter it, so this class read
    # as 16 public methods under ABSTRACTION no matter how it was arranged. That
    # is the idiom being measured, not the surface — the historical fold-spine
    # finding was a scanner-coverage defect, not a request to split this class.
    # Unlike Memory, this class did not need splitting:
    # its count was the idiom, and Memory's was the design.
    private_class_method :default_rules, :configuration_invariant_rule, :no_secret_rule, :ruby_parses_rule,
                         :scan_clean_rule, :reason_rule,
                         :safe_exec_rule, :sandboxed_exec_rule, :read_only_probe_rule, :structured_exec_rule, :batch_delete_rule, :delete_operands,
                         :operands_after_flags, :git_command_parts, :git_clean_dry_run?, :git_clean_all?,
                         :preserved_asset_delete_reason, :forbidden_file_rule, :scope_creep_rule,
                         :two_hats_rule, :evidence_for_done_rule,
                         :git_commit_evidence_rule, :git_commit_scope_rule, :council_for_done_rule,
                         :ideation_before_write_rule, :new_path_rule, :openbsd_manual_preflight_rule, :effect_reversibility_rule, :ruby_syntax_error, :safe_rx

    # One answer to "may an automated writer write or commit this path?".
    #
    # The sacred-path list retired (operator decree 2026-11-09). The Fold,
    # /fix and its autofix, a tool write and a runtime commit are refused only
    # a preserved asset (Soul.preserved_asset?), whatever MASTER_SACRED_WRITES
    # says. A person changes such a file with an ordinary git commit.
    class Paths
      REFUSAL = "is a preserved project asset: automated modification is refused"

      def self.sacred?(path, root:)
        Master::Ground::Immutability.preserved?(path, root: File.expand_path(root.to_s))
      end

      # Why no automated writer may write or commit this path, or nil. root is
      # the tree the caller works in; nil means the repository checkout.
      def self.write_refusal(path, root: nil)
        workspace = root ? File.expand_path(root.to_s) : Master::REPO_ROOT
        return unless sacred?(path, root: workspace)

        "#{path} #{REFUSAL}"
      end
    end
  end
end
