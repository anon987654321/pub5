# frozen_string_literal: true

require "json"
require_relative "../test_helper"
require_relative "../../master/models/dispatch"

# Every model call through one door, ending in the ledger: a stub `claude`
# that answers in the json result shape, and a stub HTTP transport. Moved from
# pub4's cli_usage.rb and cli_sender.rb behaviour (their tests lived inside
# test_llm_dispatcher.rb, which drove ruby_llm and is not moved).
class DispatchTest < Minitest::Test
  include TestHelper

  VERBS = { read: ["log/master/*"], write: ["log/master/*"], exec: %w[claude grok], llm: %w[anthropic openrouter] }.freeze
  RESULT = { "type" => "result", "is_error" => false, "result" => "hei fra claude",
             "usage" => { "input_tokens" => 10, "cache_read_input_tokens" => 90, "output_tokens" => 7 },
             "total_cost_usd" => 0.0123 }.freeze

  # A transport that answers like Anthropic's Messages API.
  class Transport
    attr_reader :asked

    def initialize(status = 200) = (@status = status) && (@asked = [])

    def request(_method, url, headers:, body:, timeout:)
      @asked << [url, body]
      json = { content: [{ text: "hei fra api" }], usage: { input_tokens: 5, output_tokens: 3 } }
      Core::HTTP::Reply.new(status: @status, headers: {}, body: JSON.generate(json))
    end
  end

  def stub_bin(root, name, script)
    put(root, "bin/#{name}", "#!/usr/bin/env ruby\n#{script}")
    File.chmod(0o755, File.join(root, "bin", name))
  end

  def dispatch(root, env: {}, transport: Transport.new)
    w = world(root, VERBS, env:, transport:)
    k = knobs(env)
    catalog = Models::Catalog.new
    lanes = Models::Lanes.new(catalog:, store: Models::Lanes::Store.new(w))
    router = Models::Router.new(catalog:, lanes:, knobs: k)
    gate = Models::Gate.new(lanes:, sleeper: ->(_s) { flunk "nothing should wait" })
    @said = []
    Models::Dispatch.new(world: w, catalog:, lanes:, router:, gate:, knobs: k, say: ->(l) { @said << l },
                         bin_dir: File.join(root, "bin"))
  end

  def test_a_claude_lane_answer_lands_in_the_ledger_with_its_tokens_and_cost
    sandbox do |root|
      stub_bin(root, "claude", "STDIN.read\nputs #{JSON.generate(RESULT).inspect}")
      d = dispatch(root, env: { "PUB5_MODEL" => "claude-cli:claude-opus-5-5" })
      reply = d.ask("hei")

      assert_equal "hei fra claude", reply.text
      llm = d.instance_variable_get(:@world).ledger.entries.find { |e| e["kind"] == "llm" }
      assert_equal ["claude-cli", "claude-opus-5-5", 100, 7, 0.0123, true],
                   llm.values_at("provider", "model", "tokens_in", "tokens_out", "cost_usd", "subscription")
      exec = d.instance_variable_get(:@world).ledger.entries.find { |e| e["verb"] == "exec" }
      assert_includes exec["unset"], "CLAUDECODE", "a claude child never inherits the parent session"
      assert_includes exec["argv"], "--strict-mcp-config", "a lane answers in text, with no tools"
    end
  end

  def test_an_http_answer_is_recorded_by_core_and_returned
    sandbox do |root|
      transport = Transport.new
      d = dispatch(root, env: { "PUB5_MODEL" => "claude-opus-5-5", "ANTHROPIC_API_KEY" => "k" }, transport:)
      reply = d.ask("hei", system: "terse")

      assert_equal ["hei fra api", 5, 3], [reply.text, reply.tokens_in, reply.tokens_out]
      assert_equal "terse", transport.asked.first.last[:system]
      assert_equal 1, d.instance_variable_get(:@world).ledger.spend["calls"]
    end
  end

  def test_browser_pngs_are_sent_to_an_image_capable_http_lane
    sandbox do |root|
      transport = Transport.new
      d = dispatch(root, env: { "ANTHROPIC_API_KEY" => "key" }, transport:)
      png = "\x89PNG\r\n\x1a\n".b + "fixture"
      image = { media_type: "image/png", data: Base64.strict_encode64(png) }

      reply = d.ask_with_image("Inspect this browser page.", image:, system: "Use the screenshot.")

      request = transport.asked.first.last
      blocks = request.fetch(:messages).last.fetch(:content)
      assert_equal "hei fra api", reply.text
      assert_equal "claude-sonnet-5-5", reply.model
      assert_equal "Inspect this browser page.", blocks.first.fetch(:text)
      assert_equal "image", blocks.last.fetch(:type)
      assert_equal Base64.strict_encode64(png), blocks.last.dig(:source, :data)
      assert_equal "image/png", blocks.last.dig(:source, :media_type)
    end
  end

  def test_browser_images_reject_non_png_payloads
    sandbox do |root|
      d = dispatch(root, env: { "ANTHROPIC_API_KEY" => "key" })

      assert_raises(ArgumentError) do
        d.ask_with_image("Inspect this.", image: { media_type: "image/png", data: Base64.strict_encode64("not a PNG") })
      end
    end
  end

  def test_the_subscription_limit_is_a_quota_not_a_reply
    sandbox do |root|
      limit = RESULT.merge("result" => "You've hit your session limit - resets 4:30pm")
      stub_bin(root, "claude", "puts #{JSON.generate(limit).inspect}")
      d = dispatch(root, env: { "PUB5_MODEL" => "claude-cli:claude-opus-5-5" })

      error = assert_raises(Models::Dispatch::Exhausted) { d.ask("hei") }
      assert_match(/hit your session limit/, error.message)
      assert_match(/claude-cli quota spent 1h/, @said.first)
    end
  end

  def test_a_failing_lane_cools_off_and_the_next_lane_answers
    sandbox do |root|
      stub_bin(root, "claude", "warn 'boom'\nexit 1")
      stub_bin(root, "grok", "STDIN.read\nputs 'hei fra grok'")
      d = dispatch(root)
      reply = d.ask("refactor the store") # code route: claude-cli first, grok-cli:auto after it

      assert_equal "grok-cli:auto", reply.model
      assert_equal "hei fra grok", reply.text
      assert_match(/claude-cli cooling off 30s \(claude-cli: boom\)/, @said.first)
      grok = d.instance_variable_get(:@world).ledger.entries.find { |e| e["provider"] == "grok-cli" }
      assert grok["estimated"], "a lane without usage is billed an estimate, marked as one"
      assert_nil grok["cost_usd"], "unmeasured, never zero"
    end
  end

  def test_offline_refuses_every_lane_without_cooling_any
    sandbox do |root|
      stub_bin(root, "claude", "flunk")
      d = dispatch(root, env: { "PUB5_OFFLINE" => "1", "PUB5_MODEL" => "claude-cli:claude-opus-5-5" })

      assert_raises(Core::Refusal) { d.ask("hei") }
      assert d.lanes.usable?("claude-cli:claude-opus-5-5")
    end
  end

  def test_a_spent_budget_refuses_the_cli_lane_too
    sandbox do |root|
      stub_bin(root, "claude", "STDIN.read\nputs #{JSON.generate(RESULT).inspect}")
      d = dispatch(root, env: { "PUB5_RUN_BUDGET_USD" => "0.01", "PUB5_MODEL" => "claude-cli:claude-opus-5-5" })
      d.ask("one")

      assert_raises(Core::Refusal) { d.ask("two") }
    end
  end

  def test_a_missing_binary_stands_the_lane_down
    sandbox do |root|
      d = dispatch(root, env: { "PUB5_MODEL" => "claude-cli:claude-opus-5-5" })

      assert_raises(Models::Dispatch::Exhausted) { d.ask("hei") }
      assert_match(/claude-cli: down/, d.lanes.verdict("claude-cli:claude-opus-5-5"))
    end
  end
end
