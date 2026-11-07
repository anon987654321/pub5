# frozen_string_literal: true

require "fileutils"
require "open3"
require "openssl"
require "yaml"
require_relative "env"
require_relative "../device"
require_relative "../ground/personal_permissions"

module Master
  module Mobile
    # The SMS command surface, behind three locked doors: the profile switch in
    # data/mobile.yml is off by default; the person has granted both the reading
    # and the answering scope in the permission ledger; and the only number that
    # reaches the executor is one the profile allows, matched exactly. Nothing a
    # message says is ever passed to a shell: a command is a key into a closed
    # argv map, the replies are capped, and one poll is one termux tool call
    # with no other effect on the phone.
    class Gateway
      Result = Data.define(:from, :command, :ok, :reply)

      # Command bodies map to fixed argv, never to free-form shells. A command
      # here must be readable in one screen and safe to run unattended; nothing
      # in this map writes. The test pins the map.
      COMMANDS = {
        "status" => %w[bin/operator status],
        "doctor" => %w[bin/master-mobile doctor],
      }.freeze

      KNOWN_COMMANDS = %w[status doctor help].freeze
      HELP = "MASTER knows: #{KNOWN_COMMANDS.join(' ')} commands. Prefix them with MASTER: and send to this phone."
      UNRECOGNIZED = "unknown MASTER: command - known commands: #{KNOWN_COMMANDS.join(' ')}"
      BATTERY_DEFERRED = "battery below the gateway floor - command deferred"

      READ_SCOPE = "messages"
      SEND_SCOPE = "external_messages"
      READ_PURPOSE = "accept operator commands by SMS on this phone"
      SEND_PURPOSE = "answer a MASTER command by SMS on this phone"

      MAX_COMMAND_CHARS = 200
      SEEN_KEEP = 200

      # Warn-only scam triage. Heuristics stay local, on this phone, in one
      # place: the person is warned, and the person decides. The scout never
      # deletes, never answers, and never sends a body anywhere.
      SCAM_PATTERNS = [
        /\b(urgent|immediately|asap|final (warning|notice))\b/i,
        /\b(otp|verification code|account (is )?(locked|suspended|blocked))\b/i,
        /\b(click|tap)\b|\bhttps?:\/\/\S+/i,
        /\b(fee|fine|customs|refund|prize|invoice|payment|vipps|gevinn)\b/i,
        /\b(posten|toll|bank|police|dhl|bring|post office)\b/i,
      ].freeze

      Battery = Data.define(:percent, :charging) do
        def blocks?(floor)
          charging == false && percent.is_a?(Integer) && percent < floor
        end
      end

      def initialize(root: Master::ROOT, config: Mobile.config, permissions: nil,
                     poll: nil, sender: nil, executor: nil, battery: nil, notifier: nil)
        @root = File.expand_path(root)
        @config = config.is_a?(Hash) ? config.fetch("gateway", {}) : {}
        @permissions = permissions || Master::Ground::PersonalPermissions.new(root: @root)
        @poll = poll
        @sender = sender
        @executor = executor
        @battery = battery
        @notifier = notifier
      end

      def interval_s = Integer(@config["interval_s"] || 30)
      def prefix = @config["prefix"].to_s
      def max_reply_chars = Integer(@config["max_reply_chars"] || 320)
      def battery_floor = Integer(@config["battery_floor_percent"] || 15)

      # What keeps the gateway from running, as one instruction the person can
      # act on. Nil means it may run. Ordered cheapest check first.
      def disabled_reason
        return "not a phone: Termux was not detected" unless Env.termux?
        return "gateway is off: set gateway.enabled in data/mobile.yml" unless @config["enabled"] == true

        unless Env.on_path?("termux-sms-list") && Env.on_path?("termux-sms-send")
          return "termux-sms tools unavailable: install the termux-api package"
        end

        missing_grant(READ_SCOPE, READ_PURPOSE) || missing_grant(SEND_SCOPE, SEND_PURPOSE)
      end

      def poll_once
        return [] if disabled_reason

        seen = load_seen
        handled = seen.dup
        results = unread.filter_map do |message|
          key = seen_key(message)
          next nil if handled.include?(key)

          result = handle(message)
          unless result
            result = triage(message) if scout_enabled?
          end
          handled << key if result
          result
        end
        remember_seen(handled)
        results
      end

      def run_forever
        loop do
          poll_once
          sleep(cadence_s)
        end
      rescue Interrupt
        :stopped
      end

      # A below-floor discharging phone polls five times slower: the gate that
      # defers commands needs no re-asking every thirty seconds to say so.
      def cadence_s
        interval_s * (battery_defers? ? 5 : 1)
      end

      private

      def missing_grant(scope, purpose)
        return nil if @permissions.allowed?(scope:, purpose:)

        "#{scope} consent required: /privacy grant #{scope} --confirm \"GRANT #{scope}\""
      end

      def unread
        (@poll || default_poller).call
      end

      def default_poller
        limit = Integer(@config["poll_limit"] || 5)
        -> do
          output, _status = Open3.capture2e("termux-sms-list", "-l", limit.to_s)
          JSON.parse(output)
        end
      end

      # One message at a time. A body without the prefix is the person's own
      # correspondence: it is skipped and never recorded. A body from a number
      # outside allowed_numbers is refused without a reply, because the sender
      # never established the right to one.
      def handle(message)
        number = message["number"].to_s.strip
        text = message["body"].to_s.strip
        return nil unless allowed?(number, text)

        command = text.delete_prefix(prefix).strip[0, MAX_COMMAND_CHARS]
        reply, ok =
          case command
          when "help" then [HELP, true]
          when *COMMANDS.keys then run(command)
          else [UNRECOGNIZED, false]
          end
        send_reply(number, reply)
        Result.new(from: number, command:, ok:, reply:)
      end

      def allowed?(number, text)
        Array(@config["allowed_numbers"]).map { |entry| entry.to_s.strip }.include?(number) &&
          text.start_with?(prefix)
      end

      def scout_enabled? = @config.dig("scout", "enabled") == true

      # One verdict per message, warn only. A prefix-less body from outside the
      # allowlist scores against the local scam heuristics; enough hits raise
      # one notification naming the sender, and the message is never touched
      # beyond that. The notification carries the number, never the body.
      def triage(message)
        number = message["number"].to_s.strip
        text = message["body"].to_s.strip
        return nil if text.empty?
        return nil if text.start_with?(prefix)
        return nil unless number.match?(/\A\+\d{5,20}\z/)

        hits = SCAM_PATTERNS.count { |pattern| pattern.match?(text) }
        return nil if hits < Integer(@config.dig("scout", "threshold") || 2)

        notify!("possible scam SMS from #{number} (#{hits}/#{SCAM_PATTERNS.size} patterns)")
        "scout: #{hits} scam patterns flagged for #{number}"
      end

      def notify!(message)
        (@notifier || default_notifier).call(message)
      end

      def default_notifier
        ->(message) { Master::Device.notification(title: "MASTER scout", content: message) }
      end

      def run(command)
        return [BATTERY_DEFERRED, false] if battery_defers?

        output = (@executor || default_executor).call(COMMANDS.fetch(command)).to_s[0, max_reply_chars]
        [output, true]
      end

      # A battery the tool could not read defers to nothing: only a real,
      # discharged reading stops a command.
      def battery_defers?
        state = parse_battery(read_battery)
        state ? state.blocks?(battery_floor) : false
      end

      def read_battery
        (@battery || -> { Master::Device.battery }).call
      rescue Device::Error
        nil
      end

      def parse_battery(json)
        return nil unless json.is_a?(Hash)

        status = json["status"].to_s
        plugged = json["plugged"].to_s
        charging = status == "CHARGING" || status == "FULL" ||
                   (plugged != "" && plugged != "UNPLUGGED" && !status.include?("DISCHARGING"))
        percent = begin
          Integer(json["percentage"])
        rescue ArgumentError, TypeError
          nil
        end
        Battery.new(percent:, charging:)
      end

      def send_reply(number, reply)
        (@sender || default_sender).call(number, reply[0, max_reply_chars])
      end

      def default_sender
        ->(number, text) { system("termux-sms-send", "-n", number, text) }
      end

      def default_executor
        ->(argv) do
          output, _status = Open3.capture2e(*argv, chdir: @root)
          output
        end
      end

      # Termux re-reads the same inbox entries on every poll, so every handled
      # message is remembered by content digest: a duplicate text handed to the
      # executor twice would run its command again with no word from the person.
      def seen_key(message)
        ::OpenSSL::Digest::SHA256.hexdigest(
          message["number"].to_s + "\x00" + message["body"].to_s + "\x00" + message["timestamp"].to_s,
        )[0, 16]
      end

      def seen_path = File.join(@root, ".master", "mobile", "gateway_seen.yml")

      def load_seen
        Array(YAML.safe_load_file(seen_path)).map(&:to_s).uniq
      rescue StandardError
        []
      end

      def remember_seen(keys)
        dir = File.dirname(seen_path)
        FileUtils.mkdir_p(dir, mode: 0o700)
        File.write(seen_path, YAML.dump(keys.map(&:to_s).uniq.last(SEEN_KEEP)))
        File.chmod(0o600, seen_path)
      end
    end
  end
end
