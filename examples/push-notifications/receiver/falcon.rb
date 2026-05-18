#!/usr/bin/env falcon-host

require "falcon/environment/rack"

service "rack" do
  include Falcon::Environment::Rack

  count 1

  endpoint do
    Async::HTTP::Endpoint.parse('http://0.0.0.0:9293')
  end
end
