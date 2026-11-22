# frozen_string_literal: true

# One-off probe: exercise the exact CLI-lane send path the /fix model calls
# use, against the session-scoped zai-cli lane. Run from MASTER/ with the
# vendored ruby: .tools/ruby/bin/ruby scripts/probe_zai_lane.rb
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "master"

cli_sender = Master::Review::LLMDispatcher::CliSender
abort "CliSender was not loaded by boot" unless cli_sender.is_a?(Module)

class LaneProbe
  include Master::Review::LLMDispatcher::CliSender

  def text_prompt_for(messages)
    Array(messages).filter_map { |m| m[:content] || m["content"] }.join("\n\n")
  end

  def call
    send_cli_lane("zai-cli:auto", [{ role: "user", content: "Reply with exactly one word: routed" }],
                  sys: "You are a lane probe.")
  end
end

result = LaneProbe.new.call
puts "ok?    #{result.ok?}"
puts "value  #{result.ok? ? result.value![0, 200].inspect : '-'}"
puts "err    #{result.ok? ? '-' : result.message[0, 300]}"
exit(result.ok? ? 0 : 1)
