# frozen_string_literal: true

require_relative "../io/atomic_write"
require_relative "../ground/service_supervisor"
require_relative "../cli/core_bridge"
require "json"
require_relative "../../tools/backlog" if ENV["MASTER_BACKLOG_AUTORUN"] == "1"

module Master
  # Builder and CLI boot orchestration for Master.*.
  module MasterBoot
    def start_constitution_drift(container)
      return unless ENV["MASTER_DRIFT"] == "1"

      thread = Thread.new do
        result = Ground::Orders::ConstitutionDrift.new(container:).call
        unless result.ok?
          container[:bus]&.publish("constitution_drift:error", error: result.message)
        end
      rescue StandardError => e
        container[:bus]&.publish("constitution_drift:error", error: e.message)
      end
      thread.report_on_exception = false
      thread
    end

    def bootstrap_container(root: Dir.pwd)
      boot_timed("runtime preparation") { prepare_runtime! }
      boot_timed("telemetry") { init_ground(root:) }
      container = boot_timed("builder") { Builder.build(root:) }
      boot_timed("JIT") { Runtime::Jit.apply! }
      container[:native_inventory] = boot_timed("native inventory") { Runtime::NativeInventory.snapshot }
      boot_timed("admission and cognition") { init_loop(root:, container:) }
      start_constitution_drift(container)
      container
    end

    def boot_timed(name)
      return yield unless ENV["MASTER_BOOT_TIMING"] == "1"

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      if started
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round
        Trace::Dmesg.status("timing0", "#{name}=#{elapsed}ms")
      end
    end

    def init_ground(root:)
      Trace::Telemetry.bootstrap!(root:)
    end

    # BootChecks validates the data required to construct the runtime. This
    # wider inventory is diagnostic; it reports errors but does not decide
    # admission, so it must not hold the first prompt behind a full-tree read.
    def start_background_data_validation(root:, bus:)
      thread = Thread.new do
        Thread.current.priority = -3
        validate_data!(root:, bus:)
      rescue StandardError, ScriptError => e
        Trace::Dmesg.status("boot0", "data validation failed, #{e.class}: #{e.message}")
      end
      thread.abort_on_exception = false
      thread.report_on_exception = false
      thread.name = "master-data-validation" if thread.respond_to?(:name=)
      thread
    end

    def init_loop(root:, container:)
      Ground::LawHandshake::Admission.enable!
      start_background_data_validation(root:, bus: container[:bus])
      # The wide YAML inventory runs independently at low priority. The
      # admitted runtime is already built and its required data passed BootChecks;
      # this first tick persists the loaded cognitive state without waiting for
      # the diagnostic sweep to finish.
      container[:cognition] = Cognition::Mind.new(root:, bus: container[:bus], memory: container[:memory])
      container[:fix_loop]&.wire_cognition(container[:cognition])
      container[:cognition].tick!
      start_task_steward(root, container)
      Device::Agent.start!(root:, bus: container[:bus], cognition: container[:cognition],
                           standing: container[:standing])
      unless ENV["MASTER_DEVICE"] == "0"
        container[:device_perception] = Device::Perception.new(bus: container[:bus])
        container[:device_perception].start!
      end
      container[:heartbeat]&.start!
    end

    # The durable backlog mission supervises the canonical /fix command.
    # Each exact path gets its own scoped TaskContract, proof, commit and push;
    # the supervisor advances only after every path has a verified report.
    def run_backlog_task(root:, container:, mission:, bus: nil, repo_root: REPO_ROOT)
      handle = nil
      plan = JSON.parse(mission.fetch("plan").to_s)
      paths = Array(plan.fetch("scope_paths")).map(&:to_s).uniq
      raise ArgumentError, "backlog task has no exact scope paths" if paths.empty?
      raise ArgumentError, "backlog plan is not owned by the root TODO executor" unless plan["executor"] == "root_todo"

      repository = File.realpath(repo_root)
      remote, target = Master::Io::GitOperations.new(repository).push_target
      unless remote == "origin" && target == "HEAD:main"
        raise BacklogRunFailed, "DELIVERY_FAILED: backlog requires the existing origin/main checkout"
      end
      remote_url, remote_status = Master::Io::Exec.capture2e("git", "-C", repository, "remote", "get-url", "origin")
      unless remote_status.success? && remote_url.match?(%r{github[.]com[:/]}i)
        raise BacklogRunFailed, "DELIVERY_FAILED: origin is not a reachable GitHub remote"
      end
      paths.each do |relative|
        unless Backlog::ProofMap.safe_scope_path?(relative, repo_root: repository)
          raise ArgumentError, "backlog target is missing or has an unsafe path: #{relative}"
        end
      end

      handle = Fix::Mission.new(root:, bus:).start_or_resume!(
        goal: mission.fetch("goal"), scope: root, model: mission["model"], effort: mission["effort"],
        plan: mission.fetch("plan"), origin: "backlog", auto_continue: true,
        mode: mission.dig("operator", "mode") || "repair",
        intent: mission.dig("operator", "intent") || :functional_change,
      )
      raise ArgumentError, "backlog mission could not be claimed" unless handle.record&.fetch("state", nil) == "running"

      command_spec = Backlog::ProofMap.execution_spec(
        plan.fetch("done_when"), tree: plan.fetch("tree"), repo_root: repository
      )
      unless command_spec
        raise BacklogRunFailed, "ACCEPTANCE_BLOCKED: the registered done_when command is not in the bounded execution allowlist"
      end

      command = container.fetch(:commands).fetch("fix")
      reports = []
      paths.each do |relative|
        handle.hold_lease!
        result = Fix::Mission.with_namespace("fix") do
          command.call({ args: "#{relative} --intent=functional_change" })
        end
        if result.respond_to?(:ok?) && !result.ok?
          category = result.respond_to?(:category) ? result.category : :validation
          detail = result.respond_to?(:message) ? result.message : result.to_s
          raise BacklogRunFailed.new("FIX_FAILED: #{detail}", category:)
        end

        report = result.respond_to?(:value!) ? result.value!.to_s : result.to_s
        unless backlog_fix_report_passed?(report)
          raise BacklogRunFailed, "FIX_PROOF_FAILED: /fix did not return a complete proof for #{relative}"
        end
        reports << report
      end

      proof_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      proof_output, proof_status = Master::Io::Exec.capture2e(
        command_spec.fetch(:env),
        *backlog_acceptance_argv(command_spec, repository:),
        chdir: command_spec.fetch(:cwd),
        timeout: command_spec.fetch(:timeout),
        raise_on_timeout: true,
      )
      proof_duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - proof_started) * 1000).round
      unless proof_status.success?
        raise BacklogRunFailed, "ACCEPTANCE_FAILED: #{plan.fetch("done_when")} exited #{proof_status.exitstatus.inspect}"
      end

      command_proof = {
        "proof_type" => command_spec.fetch(:proof_type),
        "status" => "pass",
        "exit_status" => proof_status.exitstatus,
        "command_digest" => command_spec.fetch(:command_digest),
        "output_digest" => Digest::SHA256.hexdigest(proof_output.to_s),
        "output_bytes" => proof_output.to_s.bytesize,
        "cwd" => command_spec.fetch(:cwd_relative),
        "duration_ms" => proof_duration_ms,
      }
      CLI::CoreBridge.push_backlog_commit!(mission: handle, root: repository, bus:)

      unless handle.record_fix_proof!(
        status: "pass", scope_paths: paths, report: reports.join("\n"),
        command_proof:
      )
        raise BacklogRunFailed, "FIX_PROOF_FAILED: durable /fix proof receipt was rejected"
      end
      summary = "root TODO #{plan.fetch("item_id")}: /fix proof passed for #{paths.size} exact scope(s); origin/main verified"
      handle.finish!(summary:)
      Master::Result.ok(summary)
    rescue BacklogRunFailed => error
      handle&.block!(reason: error.message) unless handle&.record&.fetch("state", nil) == "blocked"
      Master::Result.err(error.message, category: error.category)
    rescue StandardError => error
      reason = "FIX_FAILED: #{error.class}: #{error.message}"
      handle&.block!(reason:) unless handle&.record&.fetch("state", nil) == "blocked"
      Master::Result.err(reason, category: :validation)
    end

    def backlog_acceptance_argv(spec, repository:)
      require_relative "../operator/ruby_runner"
      case spec.fetch(:launcher)
      when :bundle
        [::Operator::RubyRunner.bundle_cmd(root: repository), "exec", *spec.fetch(:argv)]
      when :ruby_bundle
        [
          ::Operator::RubyRunner.bundle_cmd(root: repository), "exec",
          ::Operator::RubyRunner.ruby_cmd(root: repository), *spec.fetch(:argv)
        ]
      when :direct
        spec.fetch(:argv)
      else
        raise ArgumentError, "unknown backlog acceptance launcher: #{spec.fetch(:launcher).inspect}"
      end
    end

    def backlog_fix_report_passed?(report)
      text = report.to_s
      return false if text.empty? || text.match?(/DELIVERY_FAILED|FIX_FAILED|fix (?:partial|failed|incomplete)\b/i)
      return false unless text.match?(/\bfix done\b/i)
      return false unless text.match?(/\bproof:\s*(?!\s*no proof ran\b)/i)
      return false unless text.match?(/hard red 0\b/i)
      return false unless text.match?(/soft red 0\b/i)
      return false if text.match?(/unmeasured [1-9]\d*\b/i)
      return false if text.match?(/review\d+:\s*(?:incomplete|complete with open findings)\b/i)

      true
    end

    class BacklogRunFailed < StandardError
      attr_reader :category

      def initialize(message, category: :validation)
        super(message)
        @category = category
      end
    end

    def start_task_steward(root, container)
      executor = if ENV["MASTER_BACKLOG_AUTORUN"] == "1" && ENV["MASTER_TASK_STEWARD"] != "0"
                   Backlog::Executor.new(root:, repo_root: REPO_ROOT)
                 end
      if executor
        status = executor.enqueue_next!
        container[:bus]&.publish("backlog_executor:intake", status:)
      end

      container[:task_steward] = Fix::TaskSteward.start!(
        root:, bus: container[:bus],
        runner: ->(goal:, mission:) {
          if mission["origin"].to_s == "backlog"
            run_backlog_task(root:, container:, mission:, bus: container[:bus], repo_root: REPO_ROOT)
          else
            CLI::CoreBridge.run(
              goal,
              root:,
              bus: container[:bus],
              model_id: mission["model"],
              mode: mission.dig("operator", "mode"),
              container:,
            )
          end
        },
        after_run: ->(mission:, result:) {
          next unless executor && mission && mission["origin"] == "backlog"
          next unless mission["state"] == "completed"
          unless executor.record_completion!(record: mission)
            container[:bus]&.publish(
              "backlog_executor:blocked",
              mission: mission["id"],
              reason: "terminal mission lacks a current-item delivery receipt; inspect summary and pending writes",
            )
            next
          end

          status = executor.enqueue_next!(model: mission["model"])
          container[:bus]&.publish("backlog_executor:intake", status:)
        },
      )
    end

    def ensure_services!(root: ROOT)
      return true if ENV["MASTER_SKIP_TTS"] == "1"

      # Termux:API speaks directly on Android; it needs neither Edge nor a
      # desktop audio player. Treat that native command as a complete path and
      # do not start an unrelated Edge worker on a phone.
      if Device.android? && Device::Audio.tts_available?
        clear_tts_degraded!
        return true
      end

      # TTS is a capability, not synonymous with the Edge daemon. On a local
      # terminal, macOS say plus afplay (or espeak plus a player) is already
      # a complete voice path; do not mark the session degraded or spend 15s
      # trying to start an Edge worker the CLI does not need.
      if Voice::Speech.available? && (!$stdout.tty? || Voice::Playback.available?)
        clear_tts_degraded!
        warm_tts_pool(root:)
        return true
      end

      result = supervise_tts(root:)
      if result.ok? && result.value!.healthy?
        clear_tts_degraded!
        true
      else
        mark_tts_degraded!(result.ok? ? result.value!.message : result.message)
        false
      end
    end

    def supervise_tts(root:)
      Ground::ServiceSupervisor.new(root:).ensure(
        name: "tts",
        start: -> { Voice::TtsSupervisor.ensure_daemon!(root:) },
        healthy: -> { Voice::Speech.edge_tts_ready? && Voice::TtsSupervisor.socket_alive?(Voice::TtsSupervisor.socket_path(root)) },
        max_restarts: 2,
        window_seconds: 300,
        wait_seconds: 5,
      )
    end

    def clear_tts_degraded!
      ENV.delete("MASTER_TTS_DEGRADED")
      ENV.delete("MASTER_TTS_REASON")
    end

    # The early return above exists so boot does not block on the Edge worker.
    # It also meant every session started with a cold pool, and the first
    # spoken reply paid the 2.5s daemon spawn on top of synthesis (measured
    # 2026-10-02). Warm on a thread: boot stays instant, the pool is ready by
    # the time a reply speaks, and a failure here says nothing — the first
    # speak re-runs ensure_daemon! and reports if it matters.
    def warm_tts_pool(root:)
      warm = Thread.new do
        Voice::TtsSupervisor.ensure_daemon!(root:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "master_boot.tts_warm")
      end
      warm.name = "tts-warmup"
    end

    def mark_tts_degraded!(reason)
      ENV["MASTER_TTS_DEGRADED"] = "1"
      ENV["MASTER_TTS_REASON"] = reason.to_s[0, 160]
      blocker = Voice::Speech.edge_tts_blocker
      if Trace::Dmesg.verbose? || ENV["MASTER_BOOT_STATUS"] == "1"
        Trace::Dmesg.status("voice0", "degraded, #{reason}")
        Trace::Dmesg.status("voice0", "edge blocker, #{blocker}") unless blocker.to_s.empty?
      else
        Trace::Dmesg.status("voice0", "unavailable, /doctor")
      end
    end

    def emit_device_status
      return unless Device.android?

      # Without Termux:API every capability is unavailable for one reason, so
      # the boot says it once; /doctor device still lists each.
      lines = Device.status_lines
      lines = lines.first(2) unless Device.termux?
      lines.each { |line| Trace::Dmesg.status("device0", line.delete_prefix("device0: ")) }
    rescue StandardError => e
      Trace::Dmesg.status("device0", "capability discovery failed, #{e.class}: #{e.message}")
    end

    # The first interactive boot on a host says what is present and what is
    # missing, each with its fix line; Device::Onboarding never raises.
    def onboard = Device::Onboarding.run!

    # A new phone gets the face's ear in the background, so the session
    # opens at once; Device::Setup says what it does as it goes.
    def set_up_device
      Device::Setup.start!
    rescue StandardError => e
      Trace::Dmesg.status("ear0", "setup did not start, #{e.class}: #{e.message}")
    end

    # Everything up to the session prints as the kernel does (Trace::Dmesg.booting);
    # the session's splash closes the boot, and its prompt prints plain. The
    # boot-status units attach inside that splash, before "root on master0".
    def boot(root: Dir.pwd)
      container = Trace::Dmesg.booting { boot_container(root:) }
      CLI::Session.new(container:)
    end

    def boot_container(root:)
      boot_timed("soul") { Soul.load! }
      boot_timed("runtime preparation") { prepare_runtime! }
      boot_timed("device status") { emit_device_status }
      boot_timed("onboarding") { onboard }
      boot_timed("device setup") { set_up_device }

      boot_timed("pledge stage 1") { Ground::Pledge.stage1_boot!(root) }
      service_ok = boot_timed("voice services") { ensure_services!(root:) }
      Trace::Dmesg.status("master0", "continuing in degraded presentation mode") unless service_ok
      container = boot_timed("container") { bootstrap_container(root:) }
      boot_timed("pledge stage 2") { Ground::Pledge.stage2_lock! }
      boot_timed("web server") { CLI::WebServer.start(container[:config]) unless ENV["MASTER_WEB"] == "0" }
      container
    end
  end
end
