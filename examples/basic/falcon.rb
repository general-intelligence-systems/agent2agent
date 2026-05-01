#!/usr/bin/env falcon-host

require "falcon/environment/rack"

service "rack" do
  include Falcon::Environment::Rack

  endpoint do
    Async::HTTP::Endpoint.parse('http://0.0.0.0:9292')
  end
end
