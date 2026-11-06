# frozen_string_literal: true

require "json"

module Models
  # Whether a lane may be asked now, and if not, why and until when. The one
  # copy of what pub4 kept in six stores (LaneSilence twice, LaneState,
  # LaneQuota, ModelSkipCache, CircuitBreaker and its registry): each caller
  # combined its own subset, so the retry walk skipped lanes selection had
  # ordered and the dispatcher sent to lanes the router had dropped.
  #
  # A failed call opens the lane's breaker for the next step of LADDER (30s,
  # then 1m, 5m, 15m, PLAN.md section 6.2); the call after it passes is the
  # half-open probe, and one answer closes the breaker. A spent quota stands
  # the lane down for QUOTA_S; a refused key or a missing binary for DEAD_S.
  # registry/models.yml lanes.dead is down by hand.
  #
  # The state is a file (log/master/lanes.json) so a one-shot `ask`, the REPL
  # and /fix read the same breaker instead of each learning it again.
  class Lanes
    LADDER = [30, 60, 300, 900].freeze
    QUOTA_S = 3_600
    DEAD_S = 3_600
    PATH = "log/master/lanes.json"
    COOL = "cool"

    # The state file through World, or nothing for a process-local breaker.
    class Store
      def initialize(world, path = PATH)
        @world = world
        @path = path
      end

      def load
        JSON.parse(@world.read(@path))
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      def save(state) = @world.write(@path, "#{JSON.pretty_generate(state)}\n", mode: 0o600)
    end

    def initialize(catalog:, store: nil, clock: -> { Time.now.to_f })
      @catalog = catalog
      @store = store
      @clock = clock
      @state = store ? store.load : {}
    end

    def lane_of(model) = @catalog.lane_of(model)

    # nil when the model may be asked; otherwise why not.
    def verdict(model)
      lane = lane_of(model)
      return "#{lane}: down by hand (registry/models.yml lanes.dead)" if @catalog.dead?(model)

      row = open_row(lane) or return nil
      "#{lane}: #{row['kind'] == COOL ? 'cooling off' : row['kind']} #{duration(row['until'] - now)} (#{row['reason']})"
    end

    def usable?(model) = verdict(model).nil?

    # Only a cool-off ends soon; a spent quota or a refused key does not, so
    # only a cool-off is worth waiting out.
    def cooling?(model) = open_row(lane_of(model))&.fetch("kind") == COOL

    def wait_s(model) = (row = open_row(lane_of(model))) ? (row["until"] - now).ceil : 0

    def succeeded(model)
      lane = lane_of(model)
      return unless @state.key?(lane)

      @state.delete(lane)
      save
    end

    # category: :quota, :dead, or anything else for a breaker step. Returns the
    # one dmesg line that says what happened to the lane.
    def failed(model, reason, category: :error)
      lane = lane_of(model)
      row = @state[lane]
      # A lane that failed long ago starts the ladder again.
      row = { "failures" => 0 } if row.nil? || row["until"].to_f + LADDER.last < now
      kind, seconds = case category
                      when :quota then ["quota spent", QUOTA_S]
                      when :dead then ["down", DEAD_S]
                      else [COOL, LADDER.fetch([row["failures"], LADDER.size - 1].min)]
                      end
      @state[lane] = { "kind" => kind, "failures" => row["failures"] + 1, "until" => now + seconds,
                       "reason" => reason.to_s.lines.first.to_s.strip[0, 160] }
      save
      "lanes0: #{lane} #{kind == COOL ? 'cooling off' : kind} #{duration(seconds)} (#{@state[lane]['reason']})"
    end

    # One line per lane that is not answering, for /lanes and the boot line.
    def report
      dead = @catalog.models.dig("lanes", "dead").to_a.map { |lane| "#{lane}: down by hand" }
      dead + @state.keys.sort.filter_map { |lane| (row = open_row(lane)) && "#{lane}: #{row['kind']} #{duration(row['until'] - now)} (#{row['reason']})" }
    end

    private

    def open_row(lane)
      row = @state[lane]
      row if row && row["until"].to_f > now
    end

    def now = @clock.call

    def save = @store&.save(@state)

    def duration(seconds)
      seconds = seconds.ceil
      return "#{seconds}s" if seconds < 60
      return "#{seconds / 60}m" if seconds < 3_600

      "#{seconds / 3_600}h#{(seconds % 3_600) / 60}m"
    end
  end
end
