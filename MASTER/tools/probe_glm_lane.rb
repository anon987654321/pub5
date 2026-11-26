# frozen_string_literal: true

# Probe the gateway lane through MASTER's real dispatcher path before a /fix
# boot. Usage: cd MASTER && ruby tools/probe_glm_lane.rb
# (no bundle exec: the entrypoint activates MASTER's isolated bundle itself)
# The lane id follows MASTER_MODEL when glm_env.sh sourced; default gateway:glm-5.3.
MASTER_ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift File.join(MASTER_ROOT, "lib")
require "boot/entrypoint"

Master::Boot::Entrypoint.prepare!(root: MASTER_ROOT)
require "master"

runtime = Master::Builder.build(root: MASTER_ROOT)
agent = runtime.respond_to?(:agent) ? runtime.agent : runtime[:agent] ||
        runtime.instance_variable_get(:@agent)
raise "no agent in runtime (#{runtime.class})" unless agent
dispatcher = agent.instance_variable_get(:@dispatcher)
raise "no dispatcher on agent (agent: #{agent.class})" unless dispatcher

lane = ENV["MASTER_MODEL"] || "gateway:glm-5.3"
result = dispatcher.send_with_cache(
  lane,
  [{ role: "user", content: "Reply with exactly: GLM-LANE-OK" }],
  system: "You are a probe.",
  stream: false,
)
if result.err?
  puts "FAIL: #{result.message}"
  exit 1
else
  puts "OK: #{result.value.to_s.slice(0, 200)}"
end
