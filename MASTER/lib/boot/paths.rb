# frozen_string_literal: true

require "digest"

# sprawl: deliberate — standalone-load contract. Four lib files require this
# with no boot order (Swallow's standalone use from MASTER/tools depends on it, see
# data/spine.yml 2026-08-11 +2); folding it into a boot file would make every
# standalone require pull early-boot code.
module MasterPaths
  ROOT = File.expand_path("../..", __dir__)
  REPO = File.expand_path("..", ROOT)
  DATA = File.join(ROOT, "data")
  REPORTS = File.join(ROOT, "reports")
  STATE = File.expand_path("~/.master")
  # The governed trees, the one list every caller reads. BIZ joins them
  # (Johann 2026-11-07: "make those chained fix commands work") — /fix
  # BIZ refused it before, and the business-plan folders were ungoverned:
  # no tree attribution, no chain membership, no snapshot. They are a
  # documents plane (html, svg, pdf), not an app fleet, so the lanes that
  # render RAILS apps stay RAILS-scoped.
  TREES = %w[MASTER RAILS OPENBSD STUDIO BIZ].freeze

  module_function

  def root = ROOT
  def repo = REPO
  def data(*parts) = File.join(DATA, *parts)
  def reports(*parts) = File.join(REPORTS, *parts)
  # MASTER_STATE_DIR relocates the private state base without changing the
  # checkout's source/config paths. Read it at call time so an operator can
  # configure it before constructing a store in this process.
  def state_base
    configured = ENV["MASTER_STATE_DIR"].to_s.strip
    configured.empty? ? STATE : File.expand_path(configured)
  end

  def state(*parts) = File.join(state_base, *parts)

  # One private /fix state family per canonical Git remote. Worktrees and
  # relocated clones of the same repository therefore share one lock and
  # journal, while unrelated repositories do not collide. A non-Git temporary
  # root retains its local .master store, which keeps isolated tests isolated.
  # MASTER_STATE_ID is an explicit stable namespace for repositories without
  # an origin remote.
  def fix_state(root:)
    input_root = File.expand_path(root)
    repository = File.basename(input_root) == "MASTER" ? File.dirname(input_root) : input_root
    explicit = ENV["MASTER_STATE_ID"].to_s.strip
    identity = explicit.empty? ? remote_identity(repository) : state_identity(explicit)
    return File.join(input_root, ".master") unless identity

    File.join(state_base, "repositories", identity, "fix")
  end

  def remote_identity(repository)
    require "open3"
    remote, status = Open3.capture2("git", "-C", repository, "config", "--get", "remote.origin.url")
    return unless status.success?

    value = remote.to_s.strip
    return if value.empty?

    value = value.sub(%r{\A(?:https?|ssh)://}, "").sub(/\Agit@/, "")
    value = value.sub(/\A[^\/@]+@/, "")
    value = value.sub(/\A([^:\/]+):/, "\\1/")
    value = value.sub(/\.git\z/i, "").downcase
    segments = value.split(/[\/:]/).reject(&:empty?)
    return unless segments.size >= 3

    slug = segments.last(2).map { |part| part.gsub(/[^a-z0-9._-]/, "-") }.join("-")
    digest = Digest::SHA256.hexdigest(value)[0, 12]
    "#{slug}-#{digest}"
  rescue StandardError
    nil
  end

  def state_identity(value)
    normalized = value.downcase.gsub(/[^a-z0-9._-]+/, "-").gsub(/\A-+|-+\z/, "")
    return if normalized.empty?

    "#{normalized[0, 48]}-#{Digest::SHA256.hexdigest(normalized)[0, 12]}"
  end
  # The mode a private state directory is tightened to: others never keep access,
  # and the owner always has it. A directory handed to a group other than the
  # caller's own keeps that group's bits, because the hand-off is deliberate: on
  # vm23 MASTER/.master is dev:master so the master Rails app, running as master,
  # reads its config and reaches the TTS sockets, and a plain 0700 locked it out.
  # Where the directory carries the caller's own group this is base unchanged.
  def private_dir_mode(dir, base = 0o700)
    stat = File.stat(dir)
    return base if stat.gid == Process.egid

    base | (stat.mode & 0o2070)
  end

  # chmod is the owner's alone: on vm23 the master app runs as master and reaches
  # the dev-owned MASTER/.master through its group, and a chmod there raised
  # EPERM and stopped the agent container booting. The owner tightens it.
  def tighten_private_dir(dir, base = 0o700)
    File.chmod(private_dir_mode(dir, base), dir) if File.owned?(dir)
  end
end
