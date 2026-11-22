# frozen_string_literal: true

# Measure rendered speech takes: duration, sample rate, channels, clipping
# and loudness. The instrument over Master::Voice::Quality.
#
#   ruby MASTER/tools/voice/quality.rb take1.wav take2.mp3
#
# One line per path, JSON, terse. A missing or unreadable file reports its
# reason instead of failing the batch; exit 1 only when a measurement itself
# errors, never when a take merely sounds wrong - taste stays with the
# operator by law.

require "json"
require_relative "../../lib/voice/quality"

failed = false
ARGV.each do |path|
  stats = Master::Voice::Quality.inspect(path)
  failed ||= stats[:reason] == :error
  puts({ path:, **stats }.to_json)
end

if ARGV.empty?
  warn "usage: ruby MASTER/tools/voice/quality.rb <audio-path>..."
  exit 2
end
exit 1 if failed
