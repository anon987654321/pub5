# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:652 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 655b041144cb280a
require_relative "master/law/universal"

Law.define(:DEGRADE_GRACEFULLY) do
  source "Release It! - graceful degradation (Michael Nygard)"
  ask "Does a partial dependency failure crash the whole operation when a bounded fallback is possible?"
  fix "Use timeouts, circuit breakers, bounded retries, or a safe fallback."
  bad <<~'X'
    weather = WeatherAPI.fetch!; render(weather)
  X
  good <<~'X'
    weather = WeatherAPI.fetch(timeout: 2) || cached_weather
  X
end
