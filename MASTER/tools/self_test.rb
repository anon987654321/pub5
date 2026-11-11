# frozen_string_literal: true

require "json"
require "rubygems"
require "time"

root = File.expand_path("..", __dir__)
checks = []
runtime = nil

add = lambda do |name, state, detail, data = {}|
  checks << { name:, status: state, detail: detail.to_s, **data }
end

begin
  require_relative "../lib/boot/entrypoint"
  Master::Boot::Entrypoint.prepare!(root:)
  require_relative "../lib/master"
  require_relative "../checks/support/geometry_probe"

  supported_ruby = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3") &&
                   Gem::Version.new(RUBY_VERSION) < Gem::Version.new("4.1")
  add.call("ruby", supported_ruby ? "PASS" : "FAIL", RUBY_VERSION, path: RbConfig.ruby)

  models = Master.models_config(root:)
  add.call("model-catalogue", models.fetch("models", {}).empty? ? "FAIL" : "PASS",
           "#{models.fetch("models", {}).size} declared tiers")

  runtime = Master::Builder.build(root:)
  agent = runtime[:agent]
  raise "Builder returned no Review::Agent" unless agent&.respond_to?(:ask_once)

  add.call("builder", "PASS", "runtime services and Review::Agent constructed")
  add.call("default-model", agent.model.to_s.empty? ? "INCONCLUSIVE" : "PASS",
           agent.model.to_s.empty? ? "no boot model selected" : agent.model.to_s)

  router = agent.model_router
  pool = begin
    router.respond_to?(:pool) ? Array(router.pool(wait: false)) : []
  rescue StandardError => e
    add.call("model-pool", "INCONCLUSIVE", "#{e.class}: #{e.message.to_s.lines.first.to_s.strip}")
    []
  end
  add.call("model-pool", pool.empty? ? "INCONCLUSIVE" : "PASS",
           "#{pool.size} reachable model lane(s)", candidates: pool.first(12)) unless checks.any? { |check| check[:name] == "model-pool" }

  chrome = Deploy::CdpSession.chrome_path
  add.call("chrome", chrome ? "PASS" : "INCONCLUSIVE",
           chrome || "no Chrome/Chromium executable; run bin/operator browser install")
  zsh = Master::Io::Exec.cli_binary("zsh")
  add.call("zsh", zsh ? "PASS" : "INCONCLUSIVE",
           zsh || "zsh unavailable; shell-tool capability is limited")

  tty = $stdin.tty? && $stdout.tty?
  add.call("terminal", tty ? "PASS" : "INCONCLUSIVE",
           tty ? "stdin/stdout are terminals" : "self-test ran without a full interactive TTY",
           stdin_tty: $stdin.tty?, stdout_tty: $stdout.tty?)

  add.call("llm-completion", "INCONCLUSIVE",
           "no completion was sent by --self-test; use /doctor keyless for a live anonymous POST probe")
rescue SystemExit => e
  add.call("boot", "FAIL", "boot preparation exited with status #{e.status}")
rescue StandardError => e
  add.call("boot", "FAIL", "#{e.class}: #{e.message.to_s.lines.first.to_s.strip}",
           location: e.backtrace&.first.to_s)
end

overall = if checks.any? { |check| check[:status] == "FAIL" }
            "FAIL"
          elsif checks.any? { |check| check[:status] == "INCONCLUSIVE" }
            "INCONCLUSIVE"
          else
            "PASS"
          end
receipt = {
  schema: "master-self-test/v1",
  generated_at: Time.now.utc.iso8601,
  root: root,
  status: overall,
  checks: checks,
}
puts JSON.pretty_generate(receipt)
exit(overall == "FAIL" ? 1 : 0)
