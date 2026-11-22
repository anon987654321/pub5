#!/usr/bin/env -S falcon-host
# frozen_string_literal: true

# Falcon's production host interface; do not use the development-only `serve` command here.
require "falcon/environment/rack"

service "mrdamascy" do
  include Falcon::Environment::Rack

  count 1
  def container_options
    super.merge(health_check_timeout: 300)
  end

  preload "preload.rb"
  port { ENV.fetch("PORT", 47314).to_i }

  # relayd terminates TLS and is the only public entrypoint.
  endpoint do
    Async::HTTP::Endpoint
      .parse("http://127.0.0.1:#{port}")
      .with(protocol: Async::HTTP::Protocol::HTTP11)
  end
end
