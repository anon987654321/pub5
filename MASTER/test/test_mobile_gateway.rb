# frozen_string_literal: true

require "test_helper"
require "mobile/gateway"
require "ground/personal_permissions"

# The SMS operator gateway. Every test drives poll_once with stubbed termux
# tools; no test touches a real phone, a real inbox, or a shell.
class TestMobileGateway < Minitest::Test
  Permissions = Master::Ground::PersonalPermissions

  ALLOWED = "+4791234567"

  def gateway(config: {}, permissions: nil, poll: nil, executor: nil, sender: nil, battery: nil, root: nil)
    dir = root
    raise "blockless gateway needs a root" if dir.nil?

    permissions ||= Permissions.new(root: dir).tap { |ledger| grant_both!(ledger) }
    @messages ||= [sms]

    Master::Mobile::Gateway.new(
      root: dir,
      config: full_config(config),
      permissions:,
      poll: poll || -> { messages },
      executor:,
      sender:,
      battery:,
    )
  end

  def grant_both!(ledger)
    ledger.grant(scope: "messages", confirmed_by: "test", purpose: Master::Mobile::Gateway::READ_PURPOSE)
    ledger.grant(scope: "external_messages", confirmed_by: "test", purpose: Master::Mobile::Gateway::SEND_PURPOSE)
  end

  def full_config(overrides)
    { "gateway" => {
      "enabled" => true,
      "prefix" => "MASTER:",
      "interval_s" => 30,
      "poll_limit" => 5,
      "max_reply_chars" => 320,
      "battery_floor_percent" => 15,
      "allowed_numbers" => [ALLOWED],
    }.merge(overrides.fetch("gateway", {})) }
  end

  def sms(number: ALLOWED, body: "MASTER: status", read: false)
    { "number" => number, "body" => body, "read" => read }
  end

  def ready!
    Master::Mobile::Env.stub(:termux?, true) do
      Master::Mobile::Env.stub(:on_path?, true) do
        yield
      end
    end
  end

  def test_off_by_default_means_the_profile_switch
    Dir.mktmpdir do |dir|
      gateway = Master::Mobile::Gateway.new(root: dir, config: { "gateway" => {} })

      assert_match(/gateway is off/, Master::Mobile::Env.stub(:termux?, true) { gateway.disabled_reason })
      assert_match(/gateway.enabled/, Master::Mobile::Env.stub(:termux?, true) { gateway.disabled_reason })
    end
  end

  def test_a_desktop_is_never_a_gateway
    Dir.mktmpdir do |dir|
      gateway = Master::Mobile::Gateway.new(root: dir, config: { "gateway" => { "enabled" => true } })

      refute Master::Mobile::Env.stub(:termux?, false) { gateway.disabled_reason.nil? }
      assert_match(/not a phone/, Master::Mobile::Env.stub(:termux?, false) { gateway.disabled_reason })
    end
  end

  def test_both_consents_are_required_before_the_gateway_reads
    Dir.mktmpdir do |dir|
      permissions = Permissions.new(root: dir)
      gateway = Master::Mobile::Gateway.new(root: dir, config: { "gateway" => { "enabled" => true } },
                                            permissions:)

      reason = ready! { gateway.disabled_reason }

      assert_match(%r{/privacy grant messages}, reason)
    end
  end

  def test_a_missing_sms_tool_names_the_package_instead_of_polling
    Dir.mktmpdir do |dir|
      gateway = Master::Mobile::Gateway.new(root: dir, config: { "gateway" => { "enabled" => true } })

      reason = Master::Mobile::Env.stub(:termux?, true) do
        Master::Mobile::Env.stub(:on_path?, false) { gateway.disabled_reason }
      end

      assert_match(/termux-api/, reason)
    end
  end

  def test_a_known_command_runs_its_fixed_argv_and_replies
    Dir.mktmpdir do |dir|
      ran = []
      sent = []
      gateway = gateway(root: dir, executor: ->(argv) { ran << argv; "1 run, 0 failures" },
                        sender: ->(number, reply) { sent << [number, reply] })

      results = ready! { gateway.poll_once }

      assert_equal 1, results.size
      assert results.first.ok
      assert_equal "status", results.first.command
      assert_equal [%w[bin/operator status]], ran
      assert_equal [[ALLOWED, "1 run, 0 failures"]], sent
    end
  end

  def test_a_known_command_maps_to_no_writing_and_no_shell
    Master::Mobile::Gateway::COMMANDS.each_value do |argv|
      assert_equal 0, argv.first.index("bin/"), "#{argv.first} is a repository entrypoint"
      assert argv.none? { |part| part.start_with?("-") }, "#{argv.first} runs no flags"
      refute argv.join(" ").include?(";"), "no shell punctuation in #{argv.join(' ')}"
    end
  end

  def test_a_body_without_the_prefix_is_the_persons_own_mail
    Dir.mktmpdir do |dir|
      ran = []
      sent = []
      @messages = [sms(body: "lunch at three?"), sms(number: ALLOWED, body: "MASTER: status")]
      gateway = gateway(root: dir, executor: ->(argv) { ran << argv; "ok" },
                        sender: ->(number, reply) { sent << [number, reply] })

      results = ready! { gateway.poll_once }

      assert_equal 1, results.size, "the unprefixed body is skipped, never recorded"
      assert_equal ["status"], results.filter_map(&:command)
    end
  end

  def test_a_number_outside_the_allowlist_gets_no_reply
    Dir.mktmpdir do |dir|
      ran = []
      sent = []
      @messages = [sms(number: "+4798765432", body: "MASTER: status")]
      gateway = gateway(root: dir, executor: ->(argv) { ran << argv; "ok" },
                        sender: ->(number, reply) { sent << [number, reply] })

      results = ready! { gateway.poll_once }

      assert_empty results
      assert_empty ran
      assert_empty sent, "the sender never established the right to one"
    end
  end

  def test_the_allowlist_matches_exactly_not_by_suffix
    Dir.mktmpdir do |dir|
      @messages = [sms(number: "4791234567", body: "MASTER: status")]
      ran = []
      gateway = gateway(root: dir, executor: ->(argv) { ran << argv; "ok" },
                        sender: ->(*) {})

      results = ready! { gateway.poll_once }

      assert_empty results
      assert_empty ran
    end
  end

  def test_an_unrecognized_command_asks_for_help_once
    Dir.mktmpdir do |dir|
      @messages = [sms(body: "MASTER: reformat everything")]
      sent = []
      gateway = gateway(root: dir, executor: ->(*) { raise "not executed" },
                        sender: ->(_number, reply) { sent << reply })

      results = ready! { gateway.poll_once }

      refute results.first.ok
      assert_equal 1, sent.size
      assert_match(/known commands: status doctor/, sent.first)
    end
  end

  def test_help_answers_without_running_anything
    Dir.mktmpdir do |dir|
      @messages = [sms(body: "MASTER: help")]
      ran = []
      sent = []
      gateway = gateway(root: dir, executor: ->(argv) { ran << argv; "never" },
                        sender: ->(number, reply) { sent << [number, reply] })

      results = ready! { gateway.poll_once }

      assert_equal 1, results.size
      assert_equal "help", results.first.command
      assert_empty ran
      assert_match(/status doctor help/, sent.first[1])
    end
  end

  def test_a_discharged_battery_defers_and_says_so
    Dir.mktmpdir do |dir|
      @messages = [sms(body: "MASTER: status")]
      ran = []
      sent = []
      gateway = gateway(root: dir, executor: ->(argv) { ran << argv; "ok" },
                        sender: ->(number, reply) { sent << [number, reply] },
                        battery: -> { { "percentage" => 10, "status" => "DISCHARGING", "plugged" => "UNPLUGGED" } })

      results = ready! { gateway.poll_once }

      assert_equal 1, results.size
      refute results.first.ok
      assert_empty ran
      assert_match(/deferred/, sent.first[1])
    end
  end

  def test_a_charging_battery_does_not_defer
    Dir.mktmpdir do |dir|
      @messages = [sms(body: "MASTER: status")]
      ran = []
      gateway = gateway(root: dir, executor: ->(argv) { ran << argv; "ok" },
                        sender: ->(*) {},
                        battery: -> { { "percentage" => 10, "status" => "CHARGING", "plugged" => "PLUGGED_AC" } })

      ready! { gateway.poll_once }

      assert_equal [["bin/operator", "status"]], ran
    end
  end

  def test_an_unmeasured_battery_never_stops_a_command
    Dir.mktmpdir do |dir|
      @messages = [sms(body: "MASTER: status")]
      ran = []
      gateway = gateway(root: dir, executor: ->(argv) { ran << argv; "ok" },
                        sender: ->(*) {},
                        battery: -> { raise Master::Device::Error, "tool not present" })

      ready! { gateway.poll_once }

      assert_equal [["bin/operator", "status"]], ran
    end
  end

  def test_a_reply_is_capped_before_it_leaves
    Dir.mktmpdir do |dir|
      @messages = [sms(body: "MASTER: status")]
      sent = []
      gateway = gateway(root: dir, executor: ->(argv) { "x" * 900 },
                        sender: ->(number, reply) { sent << reply },
                        battery: nil)

      ready! { gateway.poll_once }

      assert_equal 320, sent.first.length
    end
  end

  def test_the_same_message_is_not_run_twice
    Dir.mktmpdir do |dir|
      @messages = [sms(number: ALLOWED, body: "MASTER: status")]
      runs = 0
      gateway = gateway(root: dir, executor: ->(argv) { runs += 1; "ok" }, sender: ->(*) {})

      ready! { gateway.poll_once }
      ready! { gateway.poll_once }

      assert_equal 1, runs
    end
  end

  def test_a_seen_ledger_survives_a_new_gateway_and_stays_private
    Dir.mktmpdir do |dir|
      @messages = [sms(number: ALLOWED, body: "MASTER: status")]
      first = gateway(root: dir, executor: ->(argv) { "ok" }, sender: ->(*) {})
      ready! { first.poll_once }

      path = File.join(dir, ".master", "mobile", "gateway_seen.yml")
      assert File.exist?(path)
      assert_equal 0o600, (File.stat(path).mode & 0o777)
      assert_equal 0o700, (File.stat(File.dirname(path)).mode & 0o777)

      @messages = [sms(number: ALLOWED, body: "MASTER: status")]
      second = gateway(root: dir, executor: ->(argv) { raise "run again" }, sender: ->(*) {})
      results = ready! { second.poll_once }

      assert_empty results, "the second gateway process sees the same handled message"
    end
  end

  attr_reader :messages
end
