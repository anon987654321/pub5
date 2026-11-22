# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "pathname"
require "securerandom"
require "socket"
require "time"
require_relative "../io/atomic_write"
require_relative "../boot/paths"
require_relative "task_contract"
# The class is split by concern; these re-open Master::Fix::Mission and are
# registered in data/autoload.yml under reopens_a_constant_defined_elsewhere.
require_relative "mission/schema"
require_relative "mission/lock"
require_relative "mission/run_state"
require_relative "mission/lease"
require_relative "mission/state"
require_relative "mission/proof"
require_relative "mission/repository"

module Master
  module Fix
    # Mission is the durable objective. A FixLoop execution is only one attempt
    # to advance it; process death must never erase the work that remains.
    class Mission
      include ::Master::Io::AtomicWrite

      VERSION = 2
      REL_PATH = ".master/mission.json"
      LOCK_PATH = ".master/mission.lock"
      NAMESPACE_KEY = :master_fix_mission_namespace
      NAMESPACE_PATTERN = /\A[a-z][a-z0-9_-]{0,31}\z/.freeze
      MAX_GOAL_BYTES = 2_048
      MAX_PLAN_BYTES = 4_096
      LEASE_SECONDS = 300
      LEASE_RENEW_SECONDS = 60
      RETRY_BASE_SECONDS = 60
      RETRY_MAX_SECONDS = 3_600
      STATES = %w[queued running waiting completed failed blocked interrupted cancelled unknown_outcome recovery_failed].freeze
      RESUMABLE_STATES = %w[running waiting].freeze
      STAGES = %w[discover plan execute verify deliver].freeze

      attr_reader :root, :id

      # A worker that claimed a mission and then lost it. Its lease expired and another worker
      # claimed the mission, or a newer mission replaced it: a write now would land on work
      # someone else owns, so it is refused rather than made.
      class Fenced < StandardError; end

      def self.instance_id
        if @instance_pid != Process.pid
          @instance_pid = Process.pid
          @instance_id = "#{Socket.gethostname}:#{Process.pid}:#{SecureRandom.hex(8)}"
        end
        @instance_id
      end

      def self.current_namespace
        Thread.current.thread_variable_get(NAMESPACE_KEY)
      end

      # Scope a synchronous repair invocation to its own durable mission file.
      # Thread variables are deliberate: ordinary thread-local state is fiber-local
      # on modern Ruby and can leak a namespace across a scheduler boundary.
      def self.with_namespace(namespace)
        thread = Thread.current
        previous = thread.thread_variable_get(NAMESPACE_KEY)
        thread.thread_variable_set(NAMESPACE_KEY, normalize_namespace(namespace))
        yield
      ensure
        thread&.thread_variable_set(NAMESPACE_KEY, previous)
      end

      def self.normalize_namespace(value)
        return if value.nil?

        normalized = value.to_s
        raise ArgumentError, "invalid mission namespace" unless normalized.match?(NAMESPACE_PATTERN)

        normalized.freeze
      end
      private_class_method :normalize_namespace

      def initialize(root: Master::ROOT, bus: nil, checkpoint: nil, namespace: self.class.current_namespace)
        @root = File.expand_path(root)
        @state_root = MasterPaths.fix_state(root: @root)
        @namespace = self.class.send(:normalize_namespace, namespace)
        @bus = bus
        @checkpoint = checkpoint
        @id = nil
        @record = nil
        prepare_shared_state!
      end

      def record
        @record&.dup
      end

      def self.block_current(root: Master::ROOT, reason:)
        mission = new(root:)
        mission.send(:load_current_unlocked!)
        mission.block!(reason:)
        mission
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Mission.block_current")
        mission
      end

      private

      def relative(path)
        full = File.expand_path(path.to_s, @root)
        root = File.expand_path(@root)
        # The tree root itself is "."; delete_prefix below would leave it absolute.
        return "." if full == root
        return path.to_s unless full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      rescue ArgumentError
        path.to_s
      end

      def now = Time.now.utc.iso8601

      def emit(event, payload = {}, **fields)
        @bus&.publish(event, payload.merge(fields))
      rescue StandardError => e
        warn("mission0: #{e.class}: #{e.message}") if ENV["MASTER_TRACE_STRICT"] == "1"
      end
    end
  end
end
