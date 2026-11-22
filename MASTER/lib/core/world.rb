# frozen_string_literal: true

require "rbconfig"
require "securerandom"
require "time"

module Master::Core
  # World — the only thing that touches the outside. Each verb is one handler;
  # the set is closed (Master::Core::VERBS), so the blast radius of the agent is the
  # surface of this file and nothing else. The Constitution has already admitted
  # whatever arrives here, so handlers do the IO plainly — their only added duty
  # is crash-safety (writes are atomic) and honest reporting. Reversing a whole
  # effect is the Fold's job via #checkpoint/#rollback, so handlers keep no
  # second, per-write backup of their own.
  #
  # This is where the old reach/ (git, web, fs), ops/, and tools/ collapse to.
  class World
    EXEC_TIMEOUT = 120  # seconds — max time for any subprocess call
    # A subprocess killed by the timeout never exited, so there is no
    # Process::Status to report. Every caller of bounded_capture2e asks
    # `.success?`, so handing back nil turned a wedged git into a
    # NoMethodError raised from inside the fold — the one place that has to
    # stay standing when the outside world misbehaves. This stands in for the
    # missing status: not successful, no exit code.
    TimedOutStatus = Class.new do
      def success? = false
      def exitstatus = nil
      def to_s = "timed out"
    end
    TIMED_OUT = TimedOutStatus.new.freeze

    # undo is the session's journal, anything answering snapshot(path). /undo
    # pops that journal's newest entry, so a fold write that records nothing
    # leaves /undo reverting an older write instead. Injected, because core
    # reaches nothing in lib/.
    # The host supplies the process boundary. Core owns effect policy; the host
    # owns subprocess execution, cancellation and environment handling.
    def initialize(root:, ask: nil, critique_runner: nil, undo: nil, capabilities: Capabilities.for(:fix),
                   network: nil, probe: nil, browser: nil, browser_effect: nil, process_runner: nil, atomic_writer: nil, git_service: nil)
      @root = File.expand_path(root)
      @ask = ask
      @critique_runner = critique_runner
      @undo = undo
      @capabilities = capabilities
      @network = network
      @probe = probe
      @browser = browser
      @browser_effect = browser_effect
      @process_runner = process_runner
      @atomic_writer = atomic_writer
      @git_service = git_service
    end

    # The Core-owned broker. Tool adapters receive its Fiber-scoped facade;
    # the Core browser Effect receives a separate read-only WebBrowse service.
    attr_reader :browser

    # A browser Effect is offered only when both the process owner and the
    # guarded one-shot reader are present in this capability context.
    def browser?
      return false unless @capabilities.allow?(:browser) && @browser && @browser_effect&.respond_to?(:call)

      !@browser.respond_to?(:available?) || @browser.available?
    rescue StandardError
      false
    end

    # A World exposes only effects its capabilities and injected services can
    # actually perform. Constitution and World both recheck every proposal.
    def process_runner? = @process_runner&.respond_to?(:capture2e) == true
    def atomic_writer? = @atomic_writer&.respond_to?(:validate_atomic_destination) && @atomic_writer&.respond_to?(:write_atomic)
    def git_service? = @git_service&.respond_to?(:commit_from_fold) == true

    def verbs
      Master::Core::VERBS.select do |verb|
        case verb
        when :git
          process_runner? && (@capabilities.allow?(:read) || (@capabilities.allow?(:write) && git_service?))
        when :probe
          process_runner? && @probe && @capabilities.allow?(:probe)
        when :exec
          process_runner? && @capabilities.allow?(:execute)
        when :write
          atomic_writer? && @capabilities.allow?(:write)
        when :browser
          browser?
        else
          @capabilities.allow?(CAPABILITIES.fetch(verb))
        end
      end
    end

    def git_operations
      return [].freeze unless process_runner?

      operations = []
      operations << "diff" if @capabilities.allow?(:read)
      operations << "commit" if @capabilities.allow?(:write) && git_service?
      operations.freeze
    end

    def perform(effect)
      @capabilities.require!(effect.capability)
      send("do_#{effect.verb}", **effect.args)
    rescue StandardError => e
      Observation.no("#{e.class}: #{e.message}")
    end

    def checkpoint
      {
        id: SecureRandom.hex(8),
        patch: worktree_patch,
      }
    end

    # Undo one failed effect — and only what that effect touched.
    #
    # The Fold takes a checkpoint immediately before each effect and rolls back
    # if that single effect errored, so the blast radius that is CORRECT here is
    # one effect's worth. What this did instead was `git reset --hard HEAD`,
    # which discards every uncommitted change in the working tree, and then
    # re-applied the checkpoint patch — a patch of tracked modifications as they
    # stood a moment earlier.
    #
    # In this repo that is destructive. The checkout is shared: other sessions
    # and a human edit it concurrently, and CLAUDE.md exists because that has
    # already cost real work. Anything another session changed between the
    # checkpoint and the failure was outside the patch and gone, and
    # anything they had staged lost its staged state either way. Undoing one
    # failed write by discarding everyone's uncommitted work is a worse outcome
    # than the write.
    #
    # So: a write is undone at its own path, which is known exactly. Anything
    # else has an unknown blast radius, and for those the honest answer is to say
    # the effect was not rolled back rather than to guess with `reset --hard`.
    # PRESERVE_FIRST and SURFACE_ERRORS_FIRST are both soul.yml code_rules; a
    # loud un-undone exec obeys them, a silent tree-wide reset obeys neither.
    def rollback(checkpoint, effect = nil)
      path = rollback_path(effect)

      # No path to scope to. An empty checkpoint means there was nothing to undo
      # in the first place; anything else is an effect whose reach is unknown.
      unless path
        return Observation.ok("rollback: clean #{checkpoint[:id]}") if checkpoint[:patch].to_s.empty?

        return Observation.no("rollback skipped #{checkpoint[:id]}: no path to scope to, and a tree-wide " \
                              "reset would discard concurrent work in this shared checkout")
      end

      # Scoped, so the checkpoint being empty is not a reason to skip: it means
      # the path was unmodified then, and restoring it to HEAD is exactly right.
      # The old early return here is why a write that dirtied a clean tree and
      # then failed was never undone at all.
      restore_path(path, checkpoint[:patch])
      Observation.ok("rolled back #{path} #{checkpoint[:id]}")
    rescue StandardError => e
      Observation.no("rollback failed: #{e.class}: #{e.message}")
    end

    # Paths are sandboxed to root; public so Fix::Transaction shares the sandbox.
    def within(path)
      raise "credential path refused: #{path}" if secret_path?(path)
      abs = File.expand_path(path, @root)
      raise "path escapes workspace: #{path}" unless under_root?(abs, @root)

      # expand_path does not follow a symlink the agent just created with ln.
      # realpath of the existing ancestor must still sit under the real root.
      real_root = File.realpath(@root)
      existing = abs
      until File.exist?(existing) || File.symlink?(existing)
        parent = File.dirname(existing)
        raise "path escapes workspace: #{path}" if parent == existing

        existing = parent
      end
      # File.exist? is false for a dangling symlink. Stop at the link itself:
      # File.realpath must reject it rather than walking past it to an in-root
      # parent and allowing mkdir_p to create through an outside target.
      resolved_existing = begin
        File.realpath(existing)
      rescue SystemCallError
        nil
      end
      raise "path escapes workspace: #{path}" unless resolved_existing && under_root?(resolved_existing, real_root)

      if File.exist?(abs)
        canonical_file = File.realpath(abs)
        raise "path escapes workspace: #{path}" unless under_root?(canonical_file, real_root)
        raise "credential path refused: #{path}" if secret_path?(canonical_file)
      end

      abs
    end

    private

    def do_read(path:, **)
      Observation.ok(File.read(within(path), encoding: "UTF-8").scrub)
    end

    # A probe is not shell access. The injected policy admits only exact,
    # read-only diagnostics; World rechecks it so a direct call cannot bypass
    # the Constitution. No model-supplied environment is accepted.
    def do_probe(argv:, timeout: 20, **)
      raise ArgumentError, "argv must be an array" unless argv.is_a?(Array)
      raise ArgumentError, "argv cannot be empty" if argv.empty?
      raise ArgumentError, "argv entries must be strings" unless argv.all? { |arg| arg.is_a?(String) }
      return Observation.no("read-only probe policy unavailable") unless @probe

      refusal = @probe.call(argv)
      return Observation.no("read-only probe refused: #{refusal}") if refusal

      seconds = Integer(timeout, exception: false)
      seconds = 20 unless seconds&.positive?
      seconds = [seconds, 30].min
      command = argv.first == "ruby" ? [RbConfig.ruby, "--disable-gems", *argv.drop(1)] : argv
      child_env = ENV.keys.grep(CREDENTIAL_ENV_RX).to_h { |name| [name, nil] }
      %w[RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS].each { |name| child_env[name] = nil }
      out, status = bounded_capture2e(*command, env: child_env, chdir: @root, timeout: seconds)
      detail = "probe result: exit=#{status.exitstatus || status}\n#{out}".strip
      status.success? ? Observation.ok(detail) : Observation.no(detail)
    end

    def do_write(path:, content:, **)
      raise "atomic writer unavailable; host must inject write_atomic" unless atomic_writer?

      abs = within(path)
      @atomic_writer.validate_atomic_destination(abs)
      @undo&.snapshot(abs)
      @atomic_writer.write_atomic(abs, content)
      Observation.ok("wrote #{path} (#{content.bytesize}b)")
    end

    def do_http(url:, **)
      return Observation.no("network unavailable") unless @network

      result = @network.call(url:)
      result.ok? ? Observation.ok(result.value!.to_s) : Observation.no(result.message.to_s)
    rescue StandardError => e
      Observation.no("http: #{e.class}: #{e.message}")
    end

    # Browser Effects are one-shot, read-only visits. The injected WebBrowse
    # owns operator permission, SSRF pinning, GET/HEAD request fencing, resource
    # budgets and ensure-based lease cleanup; Core never receives a CDP URL.
    def do_browser(url:, wait: 1.0, links: true, **)
      return Observation.no("guarded browser unavailable") unless browser?

      result = @browser_effect.call(url:, wait:, links:)
      return Observation.no("browser service returned an invalid result") unless result.respond_to?(:ok?)

      result.ok? ? Observation.ok(result.value!.to_s) : Observation.no(result.message.to_s)
    rescue StandardError => e
      Observation.no("browser: #{e.class}: #{e.message}")
    end

    def do_exec(argv:, timeout: 60, env: {}, **)
      raise ArgumentError, "argv must be an array" unless argv.is_a?(Array)
      raise ArgumentError, "argv cannot be empty" if argv.empty?
      raise ArgumentError, "argv entries must be strings" unless argv.all? { |arg| arg.is_a?(String) }

      # Model-chosen env used to ride through (LD_PRELOAD, PATH, …). The
      # constitution only inspects argv. Inherit nothing from the effect.
      seconds = timeout.to_i
      seconds = EXEC_TIMEOUT if seconds <= 0 || seconds > EXEC_TIMEOUT

      # A name mapped to nil is UNSET in the child. Passing "ENV minus credentials"
      # would do nothing instead: spawn MERGES an env hash over the inherited
      # environment, so every dropped key would be inherited straight back.
      # Unsetting by name is also why the toolchain needs no enumerating —
      # everything not matched here arrives exactly as it did before.
      # The worker sets OpenBSD execpromises before replacing itself with argv.
      # Keep those promises off this parent: trusted operator controls retain their
      # separate, explicit privilege path.
      worker = File.join(Master::ROOT, "bin", "master")
      child_env = ENV.keys.grep(CREDENTIAL_ENV_RX).to_h { |name| [name, nil] }
      # These variables run code before Ruby starts the worker, ahead of pledge.
      %w[RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS].each { |name| child_env[name] = nil }
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out, status = bounded_capture2e(
        RbConfig.ruby, "--disable-gems", worker, "--exec-worker", "--", *argv,
        env: child_env,
        chdir: @root,
        timeout: seconds
      )
      elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000
      return Observation.no(out.to_s.strip) unless status.success?

      receipt = ExecutionReceipt.from_process(
        argv:,
        exitstatus: status.exitstatus,
        output: out,
        elapsed_ms:,
      )
      Observation.ok(out.to_s.strip, execution_receipt: receipt)
    end

    # Credentials do not go into the child, because the child's output comes back.
    #
    # `env: nil` inherited the whole process environment. That was written to mean
    # "nothing the MODEL supplied rides through", and it does mean that — but the
    # process running the fold holds OPENROUTER_API_KEY, ANTHROPIC_API_KEY,
    # REPLICATE_API_TOKEN and the rest, and exec output becomes an Observation,
    # which Memory records, which the next turn hands back to the model. So
    # `exec(["env"])` was a supported way to read every key into the transcript.
    #
    # no_secret_rule already forbids a secret reaching a file or a note. It watches
    # write and note only, so the exec path — the one that flows INTO the model
    # rather than out of it — was the direction nothing covered.
    #
    # Removed by name rather than allowlisted by name. An allowlist is the safer
    # shape in general, but here it would have to enumerate the toolchain the fold
    # proves its work with — PATH, HOME, GEM_*, BUNDLE_*, RBENV_*, RUBY* — and the
    # first variable it forgot would break `bundle exec rake test`, i.e. the fold's
    # ability to earn evidence at all. Credential names are the narrow, stable set;
    # the toolchain is the broad, moving one. This drops the narrow set.
    CREDENTIAL_ENV_RX = /KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|SESSION|COOKIE|SALT|CERT|PRIVATE|
                         \A(?:AWS|GOOGLE|GCP|AZURE|STRIPE|TWILIO|SENDGRID|VAPID|DATABASE_URL)/xi

    # The Fold has stricter admission than the generic Git service: it requires
    # exact content receipts, rejects pre-staged targets and refuses deletions.
    # The shared Git service owns the private-index write itself.
    def do_git(operation:, paths: [], message: nil, expected_hashes: nil, **)
      case operation.to_s.to_sym
      when :diff then Observation.ok(git_capture("diff"))
      when :stage then Observation.no("git stage is not a separate action; use a path-scoped commit after proof")
      when :commit
        return Observation.no("git commit service unavailable") unless git_service?

        do_git_commit(Array(paths), message, expected_hashes:)
      else Observation.no("unknown git operation: #{operation}")
      end
    end

    # Every commit the runtime makes carries this trailer, and every commit
    # site reads it from here. Everything in this checkout commits as one
    # author, so the trailer is the only thing `git log --grep` can tell a
    # runtime commit from a human one by.
    COMMIT_TRAILER = "Co-authored-by: MASTER"

    def do_git_commit(paths, message, expected_hashes: nil)
      scoped = Array(paths).map(&:to_s).reject(&:empty?).uniq
      return Observation.no("git commit needs explicit paths") if scoped.empty?

      expected = expected_hashes.is_a?(Hash) ? expected_hashes.to_h { |path, digest| [path.to_s, digest.to_s] } : {}
      return Observation.no("git commit needs the task's exact content receipts") unless expected.keys.sort == scoped.sort
      return Observation.no("git commit refused: malformed content receipt") unless expected.values.all? { |digest| digest.match?(/\A[0-9a-f]{64}\z/i) }

      safe_paths = scoped.map do |path|
        full = within(path)
        raise ArgumentError, "git commit path must be a file: #{path}" unless File.file?(full) && !File.symlink?(full)

        relative = full.delete_prefix(@root + File::SEPARATOR).tr(File::SEPARATOR, "/")
        raise ArgumentError, "git commit path escapes workspace: #{path}" if relative == full || relative.split("/").include?(".git")

        refusal = Constitution::Paths.write_refusal(relative, root: @root)
        raise ArgumentError, "git commit refused: #{refusal}" if refusal

        relative
      end
      return Observation.no("git commit refused: duplicate or aliased paths") unless safe_paths.uniq.sort == scoped.sort

      pathspecs = safe_paths.map { |path| ":(literal)#{path}" }
      # Porcelain v1 -z preserves status columns and paths containing whitespace.
      # A staged target belongs to its current writer, even if this fold also wrote it.
      status = git_capture("status", "--porcelain=v1", "-z", "--", *pathspecs, raw: true)
      entries = status.split("\0").reject(&:empty?)
      staged = entries.select do |entry|
        index_status = entry[0].to_s
        index_status != " " && index_status != "?"
      end
      return Observation.no("git commit refused: a requested path already has staged changes: #{staged.map { |entry| entry[3..].to_s }.join(", ")}") if staged.any?

      deleted = entries.select { |entry| entry[1] == "D" }
      return Observation.no("git commit refused: deletions need a separate reviewed operation") if deleted.any?

      untracked = entries.filter_map { |entry| entry[3..] if entry.start_with?("?? ") }
      known = git_capture("ls-files", "-z", "--", *pathspecs, raw: true).split("\0")
      unknown = safe_paths - known - untracked
      return Observation.no("git commit refused: missing or ignored paths: #{unknown.join(", ")}") if unknown.any?

      output = @git_service.commit_from_fold(
        message: message.to_s, paths: safe_paths, expected_hashes: expected, trailer: COMMIT_TRAILER,
      )
      Observation.ok(output)
    rescue StandardError => error
      Observation.no("git commit refused: #{error.class}: #{error.message}")
    end

    def do_ask(prompt:, options: nil, **)
      return Observation.no("no surface to ask") unless @ask

      Observation.ok(@ask.call(prompt:, options:))
    end

    def do_note(**) = Observation.ok # the Memory keeps the note; nothing to do here

    def do_critique(scope: "diff", **)
      return Observation.no("critique: council runner unavailable") unless @critique_runner

      result = @critique_runner.call(root: @root, scope: scope.to_s)
      result.ok? ? Observation.ok(result.value!.to_s) : Observation.no(result.message.to_s)
    rescue StandardError => e
      Observation.no("critique: #{e.class}: #{e.message}")
    end

    # Credential files, by name, inside the workspace.
    #
    # within() stops a path leaving root and says nothing about what sits
    # inside it. A .env or a credentials file in the tree was readable, and
    # reading one puts the secret in the transcript, where the constitution's
    # promise that no credential reaches disk or the transcript no longer
    # holds. Keys live in /etc/*.env on the box for this reason; this is the
    # same rule applied to the checkout.
    #
    # Name-based, so it holds for a file the agent has not read yet. Content
    # scanning cannot: by the time there is content to scan, the read has
    # happened.
    # `private` alone refused private_notes_test.rb, and a bare `keys?` let
    # api_keys.txt through by anchoring before the prefix. So: the word has to
    # be a whole leading component of the name, and `key` may carry one
    # qualifier in front of it -- api_key, private_key -- which keeps
    # keyboard.js, tokenizer.rb and environment.rb readable. A name led by one
    # of those words is still source when it ends in a source extension:
    # token_checks.rb is a check over design tokens, and refusing it crashed
    # /fix mid-pass.
    SOURCE_EXTENSION = /(?!.*\.(?:rb|rake|erb|js|mjs|ts|css|scss|md)\z)/
    SECRET_BASENAME = /
      \A(?:
        \.env(?:rc|[._-][a-z0-9._-]+)?\z |
        [a-z0-9_-]+\.env\z |
        #{SOURCE_EXTENSION}(?:credentials?|secrets?|tokens?)(?:[._-]|\z) |
        #{SOURCE_EXTENSION}(?:[a-z0-9]+[._-])?keys?(?:[._-]|\z) |
        id_(?:rsa|dsa|ecdsa|ed25519) |
        \.(?:netrc|pgpass|npmrc)\z |
        [a-z0-9._-]+\.pem\z
      )
    /xi

    # Some secrets have ordinary names and are identified only by where they
    # live. .master/config.yml holds web_token, and "config.yml" is as generic
    # as a filename gets, so the basename rule could never catch it without
    # refusing every config file in the tree.
    SECRET_PATH = %r{(?:\A|/)\.master/config\.ya?ml\z}i

    # And one ordinary file has a secret's name: data/tokens.yml is MASTER's
    # design tokens (colour, type, the face), and refusing it crashed /fix
    # mid-pass. Its place in the tree is what clears it; tokens.yml elsewhere
    # is still refused.
    DESIGN_TOKENS_PATH = %r{(?:\A|/)data/tokens\.yml\z}

    def self.secret?(path)
      text = path.to_s
      return false if DESIGN_TOKENS_PATH.match?(text)

      SECRET_BASENAME.match?(File.basename(text)) || SECRET_PATH.match?(text)
    end

    def secret_path?(path) = World.secret?(path)

    def under_root?(abs, root)
      abs == root || abs.start_with?(root + File::SEPARATOR)
    end

    def git_repo?
      _, status = bounded_capture2e("git", "-C", @root, "rev-parse", "--is-inside-work-tree")
      status.success?
    end

    def git_has_head?
      _, status = bounded_capture2e("git", "-C", @root, "rev-parse", "--verify", "HEAD")
      status.success?
    end

    # A workspace need not be a git repo. When it isn't, there is nothing to
    # capture and rollback becomes a clean no-op, so the fold still runs.
    def worktree_patch
      return "" unless git_repo?

      if git_has_head?
        git_capture("diff", "HEAD", "--binary", raw: true)
      else
        git_capture("diff", "--binary", raw: true)
      end
    end

    def git_capture(*args, raw: false, env: nil)
      out, status = bounded_capture2e("git", "-C", @root, *args, env:)
      raise out.strip unless status.success?

      raw ? out : out.strip
    end

    # Delegate to the one host-owned process supervisor. Core depends only
    # on capture2e; it does not require the wider runtime.
    def bounded_capture2e(*cmd, stdin_data: nil, env: nil, chdir: nil, timeout: nil)
      timeout_sec = Integer(timeout || ENV.fetch("MASTER_EXEC_TIMEOUT", EXEC_TIMEOUT))
      raise "process runner unavailable; host must inject capture2e" unless @process_runner&.respond_to?(:capture2e)

      options = { timeout: timeout_sec, raise_on_timeout: true }
      options[:stdin_data] = stdin_data unless stdin_data.nil?
      options[:env] = env unless env.nil?
      options[:chdir] = chdir unless chdir.nil?
      @process_runner.capture2e(*cmd, **options)
    rescue StandardError => error
      raise unless error.respond_to?(:timeout?) && error.timeout? && error.respond_to?(:result)

      output, = error.result
      ["#{output}TIMEOUT after #{timeout_sec}s: #{cmd.first}", TIMED_OUT]
    end

    # Only a write names its target up front. exec can touch anything, and git
    # operations are undone by git rather than by a patch.
    def rollback_path(effect)
      effect.args[:path].to_s.then { |p| p unless p.empty? } if effect.respond_to?(:verb) && effect.verb == :write
    end

    # Restore one path to the state the checkpoint captured.
    #
    # Two steps because the patch is a diff against HEAD: put the file back to
    # HEAD, then re-apply only this path's hunks from the checkpoint. --include
    # is what keeps the rest of the patch — other files, other sessions' work —
    # out of it.
    #
    # A path git does not know at HEAD is left exactly as it is. It could be a
    # file the effect created, but it could equally be an untracked file that was
    # already there, and nothing captured at checkpoint time tells the two apart.
    # Deleting on that guess is the one outcome that cannot be undone, and
    # test_world_rollback already pins that a pre-existing untracked file survives.
    def restore_path(path, patch)
      raise "#{path} is untracked at HEAD; left alone rather than guessed to be new" unless tracked_at_head?(path)

      git_capture("checkout", "HEAD", "--", path)
      apply_patch_for(path, patch)
    end

    def tracked_at_head?(path)
      return false unless git_has_head?

      out, status = bounded_capture2e("git", "-C", @root, "ls-tree", "--name-only", "HEAD", "--", path)
      status.success? && !out.strip.empty?
    end

    # An empty selection is not a failure: the path had no uncommitted change at
    # checkpoint time, so HEAD is already the state being restored to.
    #
    # The patch names paths from the repository's top, and --include matches
    # those names. Rooted in a subdirectory, as MASTER is in pub5, a bare path
    # matched nothing: the file went back to HEAD, the operator's uncommitted
    # edit went with it, and the rollback reported success.
    def apply_patch_for(path, patch)
      include = "#{git_capture("rev-parse", "--show-prefix")}#{path}"
      out, status = bounded_capture2e("git", "-C", @root, "apply", "--binary", "--include=#{include}", "-",
                                      stdin_data: patch)
      raise out.strip unless status.success? || out.include?("No valid patches")
    end
  end
end
