# frozen_string_literal: true

require_relative "../../../a2a/server"
require "traces/provider"

Traces::Provider(A2A::Server) do
  def call(env)
    attributes = {
      "http.method" => env["REQUEST_METHOD"],
      "http.path" => env["PATH_INFO"],
    }

    Traces.trace("a2a.server.call", attributes: attributes) do |span|
      super.tap do |status, headers, body|
        span["http.status_code"] = status
      end
    end
  end
end
