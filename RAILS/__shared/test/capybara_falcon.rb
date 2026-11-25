# frozen_string_literal: true

# System tests serve the app with Falcon, the server vm23 runs. Puma is not a
# dependency of any pub5 app: Capybara's default server would otherwise be it.
require "capybara"
require "async"
require "async/http/endpoint"
require "falcon/server"

Capybara.register_server :falcon do |app, port, host|
  endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
  Sync do
    Falcon::Server.new(Falcon::Server.middleware(app), endpoint).run.each(&:wait)
  end
end

Capybara.server = :falcon
