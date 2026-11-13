# frozen_string_literal: true

require "time"
require_relative "../result"

module Master
  module Ground
    # Stateless aggregation of security-event signals. It never returns raw
    # user IDs, IP addresses, user agents, request paths or source events.
    # Findings are triage indicators, not proof of compromise.
    class SecurityMonitor
      DEFAULTS = {
        failed_login_threshold: 5,
        suspicious_session_threshold: 5,
        unusual_api_threshold: 100,
        analysis_window_hours: 24,
      }.freeze

      def initialize(config: {}, clock: -> { Time.now.utc })
        @config = DEFAULTS.merge(config.to_h.transform_keys(&:to_sym))
        @clock = clock
        validate_config!
      end

      def analyze(events:, since: nil, until_at: nil)
        finish = until_at ? coerce_time(until_at) : now
        start = since ? coerce_time(since) : finish - (@config[:analysis_window_hours] * 3600)
        return Result.err("security_monitor: invalid analysis window", category: :validation) unless start < finish

        rows = normalize(events, start, finish)
        failed = failed_logins(rows)
        sessions = suspicious_sessions(rows)
        api = unusual_api(rows)
        score = failed[:suspicious_user_count] * 20 +
                sessions[:suspicious_user_count] * 30 +
                api[:high_volume_user_count] * 10
        Result.ok(
          schema: 1, event_count: rows.size, window: { since: start.iso8601, until: finish.iso8601 },
          score:, risk_level: risk_level(score),
          findings: { failed_logins: failed, suspicious_sessions: sessions, unusual_api: api },
          not_run: rows.empty? ? ["no events in the selected window"] : [],
          limitation: "signals require human investigation; this report does not identify or sanction an account",
        )
      rescue ArgumentError => error
        Result.err("security_monitor: #{error.message}", category: :validation)
      rescue StandardError => error
        Result.err("security_monitor: #{error.class}: #{error.message}", category: :infrastructure)
      end

      private

      def validate_config!
        @config.each do |key, value|
          next if key == :analysis_window_hours
          number = Integer(value)
          raise ArgumentError, "#{key} must be 1..100000" unless number.between?(1, 100_000)
          @config[key] = number
        end
        hours = Float(@config.fetch(:analysis_window_hours))
        raise ArgumentError, "analysis_window_hours must be 1..168" unless hours.finite? && hours.between?(1, 168)
        @config[:analysis_window_hours] = hours
      end

      def normalize(events, start, finish)
        Array(events).first(100_000).filter_map do |row|
          next unless row.is_a?(Hash)
          value = row[:at] || row["at"]
          at = coerce_time(value)
          next unless at >= start && at < finish
          {
            type: (row[:type] || row["type"]).to_s,
            at:, user: (row[:user_id] || row["user_id"]).to_s,
            ip: (row[:ip] || row["ip"]).to_s,
            country: (row[:country] || row["country"]).to_s,
            agent: (row[:user_agent] || row["user_agent"]).to_s,
            endpoint: (row[:endpoint] || row["endpoint"]).to_s,
          }
        rescue ArgumentError
          nil
        end
      end

      def failed_logins(rows)
        failures = rows.select { |row| row[:type] == "FAILED_LOGIN" }
        by_user = frequencies(failures, :user)
        by_ip = frequencies(failures, :ip)
        {
          total: failures.size,
          suspicious_user_count: by_user.values.count { |count| count >= @config[:failed_login_threshold] },
          suspicious_ip_count: by_ip.values.count { |count| count >= 10 },
        }
      end

      def suspicious_sessions(rows)
        sessions = rows.select { |row| row[:type] == "SESSION_CREATED" && !row[:user].empty? }.group_by { |row| row[:user] }
        patterns = Hash.new(0)
        suspicious = 0
        sessions.each_value do |items|
          flags = []
          flags << :rapid if items.size >= @config[:suspicious_session_threshold]
          flags << :geo if items.map { |item| item[:country] }.reject(&:empty?).uniq.size > 2
          flags << :device if items.map { |item| item[:agent] }.reject(&:empty?).uniq.size > 3
          next if flags.empty?
          suspicious += 1
          flags.each { |flag| patterns[flag] += 1 }
        end
        { total: sessions.values.sum(&:size), suspicious_user_count: suspicious, pattern_counts: patterns }
      end

      def unusual_api(rows)
        calls = rows.select { |row| row[:type] == "API_CALL" }
        users = frequencies(calls, :user)
        endpoints = frequencies(calls, :endpoint)
        {
          total: calls.size,
          high_volume_user_count: users.values.count { |count| count >= @config[:unusual_api_threshold] },
          high_volume_endpoint_count: endpoints.values.count { |count| count >= 50 },
        }
      end

      def frequencies(rows, key)
        rows.reject { |row| row[key].empty? }.group_by { |row| row[key] }.transform_values(&:size)
      end

      def risk_level(score)
        return "CRITICAL" if score >= 100
        return "HIGH" if score >= 50
        return "MEDIUM" if score >= 20
        "LOW"
      end

      def coerce_time(value)
        time = value.is_a?(Time) ? value : Time.iso8601(value.to_s)
        time.utc
      rescue ArgumentError, TypeError
        raise ArgumentError, "event timestamps must be Time or ISO-8601"
      end

      def now
        value = @clock.call
        raise TypeError, "clock must return Time" unless value.is_a?(Time)
        value.utc
      end
    end
  end
end
