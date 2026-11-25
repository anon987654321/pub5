# frozen_string_literal: true

Rails.application.config.x.master_start_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
Rails.application.config.x.master_container = nil
Rails.application.config.x.master_container_mutex = Mutex.new
Rails.application.config.x.master_bootstrap_started = false

# The test suite stubs the container in its setup. A real one built at boot
# lands on config.x whenever its thread finishes, over whatever stub the test
# then running installed, so a test of the warming path would read a live
# container or not depending on how long the boot took.
Rails.application.config.after_initialize do
  next if MasterContainerLoader.asset_task?

  MasterContainerLoader.warm_shared_namespace!
  MasterContainerLoader.rearm! unless Rails.env.test?
end

module MasterContainerLoader
  module_function

  # assets:precompile boots the whole app to resolve helpers, and it is not a
  # server -- nothing will ever serve a request from it. Building a container
  # there costs a container nobody uses and leaves a tts-worker daemon behind
  # for every precompile, which is why rc_pre kept accumulating orphaned
  # workers.
  #
  # It is not why master would not start. That was the master_web_assets check
  # refusing on face.css :root drift, which rc_pre logs to syslog while rcctl
  # prints nothing -- so the refusal read as a hang. spawn_daemon already
  # redirects the child's stdio to a log and passes close_others, so no worker
  # ever held rc.d's pipe. Recorded because the first explanation here said it
  # did, and a wrong reason in a comment outlives the bug it misdescribes.
  def asset_task?
    ARGV.any? { |arg| arg.start_with?("assets:") }
  end

  # Master::Ground is loaded here, on the main thread, before the bootstrap
  # thread below exists.
  #
  # Master carries its own Zeitwerk loader and never eager-loads, so its
  # constants resolve by autoload on first reference. Zeitwerk autoloading is
  # not thread-safe, and the web tier arranges the one collision that matters:
  # ApplicationController names Master::Ground::Tool::Profile in its class body,
  # which Rails evaluates on the first request — inside the window where the
  # bootstrap thread is autoloading Master constants of its own. The collision
  # surfaces as `uninitialized constant Master::Ground::Tool::Profile`, and it
  # takes out any request that lands in the window, including a warming probe.
  #
  # 160 ms for the namespace, once, against a container bootstrap measured in
  # seconds. Eager-loading all of Master would cost 941 ms and delay /up, which
  # is the thing the bootstrap thread exists to avoid.
  def warm_shared_namespace!
    Master::LOADER.eager_load_namespace(Master::Ground)
  rescue StandardError => e
    Rails.logger.warn("master_container: could not warm Master::Ground: #{e.class}: #{e.message}")
  end

  # Arms exactly one bootstrap thread and remains safe on every request that
  # finds no container. The mutex owns the claim, so concurrent requests share
  # one bootstrap attempt instead of starting duplicate threads.
  #
  # ApplicationController#require_container! calls this when the container is
  # absent; a later request can re-arm a failed or lost bootstrap.
  def rearm!(config = Rails.application.config)
    return config.x.master_container if config.x.master_container

    claimed = config.x.master_container_mutex.synchronize do
      next false if config.x.master_bootstrap_started

      config.x.master_bootstrap_started = true
    end
    Thread.new { ensure! } if claimed
    nil
  end

  # The asset-task guard sits here as well as in after_initialize because every
  # path to a container ends in ensure!, including rearm! from
  # ApplicationController, so the guard cannot be walked around. rc_pre
  # runs assets:precompile as root, so a container built there spawns
  # tts-worker as root and leaves .master/tts-worker-*.log root-owned, which
  # the master user then cannot write.
  # Irreversible and deliberately gated until the exact Falcon/TTS service
  # layout passes a live OpenBSD smoke. A partial native lock must not retry.
  def seal_native_web!(root)
    require "master" unless defined?(Master::Ground::Pledge)
    guard = Master::Ground::Pledge
    sockets = Master::Voice::TtsSupervisor.pool_size.times.map do |index|
      Master::Voice::TtsSupervisor.socket_path(root, index:)
    end
    state = Rails.root.join("tmp", "public_runtime").to_s
    auth_path = File.expand_path(OperatorToken.config_path)
    unless auth_path.start_with?(state + File::SEPARATOR) && File.file?(auth_path) &&
        File.realpath(auth_path).start_with?(File.realpath(state) + File::SEPARATOR) && !OperatorToken.read.empty?
      raise Master::SecurityError, "native web sandbox requires a dedicated web auth file inside public_runtime"
    end
    guard.web_lock!(root:, web_root: Rails.root.to_s, auth_path:, socket_paths: sockets)
    Rails.logger.info("master_container: native web sandbox sealed")
  rescue StandardError => e
    Rails.logger.fatal("master_container: native sandbox refused: #{e.class}: #{e.message}")
    exit!(1)
  end

  def ensure!(config = Rails.application.config)
    return if asset_task?
    return config.x.master_container if config.x.master_container

    config.x.master_container_mutex.synchronize do
      return config.x.master_container if config.x.master_container

      root = Master::ROOT
      Master.prepare_runtime!
      Master::Voice::TtsSupervisor.ensure_daemon!(root:)
      TtsJob.ensure_worker!
      container = Master::Builder.build_web(root:, state_root: Rails.root.join("tmp", "public_runtime").to_s)
      seal_native_web!(root) if ENV["MASTER_WEB_NATIVE_SANDBOX"] == "1"
      config.x.master_container = container
      Rails.logger.info("master_container: ready")
      container
    end
  # The bootstrap thread has no caller to report an exception to. Keep the
  # failure visible in the Rails log and release the claim so the next request
  # can rearm the container. StandardError is the application failure boundary;
  # process-level exceptions must still terminate the process rather than being
  # swallowed by a background thread.
  rescue StandardError => e
    Rails.logger.error("master_container boot failed: #{e.class}: #{e.message}")
    config.x.master_bootstrap_started = false
    nil
  end

end
