# frozen_string_literal: true

require_relative "../../../../a2a/server/dispatcher"
require "traces/provider"

Traces::Provider(A2A::Server::Dispatcher) do
  def call(env)
    attributes = {
      "a2a.operation" => env["a2a.operation"],
    }

    Traces.trace("a2a.server.dispatcher.call", attributes: attributes) do |span|
      super.tap do |status, headers, body|
        span["http.status_code"] = status

        if env["a2a.stream"]
          span["a2a.response_type"] = "stream"
        elsif env["a2a.error"]
          span["a2a.response_type"] = "error"
        elsif env["a2a.result"]
          span["a2a.response_type"] = "result"
        end
      end
    end
  end
end
