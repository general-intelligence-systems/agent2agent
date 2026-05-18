# frozen_string_literal: true

require_relative "../../../../../a2a/server/bindings/rest"
require "traces/provider"

Traces::Provider(A2A::Server::Bindings::Rest) do
  def call(env)
    Traces.trace("a2a.bindings.rest.call") do |span|
      super.tap do |status, headers, body|
        span["http.status_code"] = status

        if verb = env["a2a.verb"]
          span["a2a.verb"] = verb
        end

        if path = env["a2a.path"]
          span["a2a.path"] = path
        end

        if env["a2a.stream"]
          span["a2a.response_type"] = "stream"
        elsif env["a2a.error"]
          span["a2a.response_type"] = "error"
        else
          span["a2a.response_type"] = "result"
        end
      end
    end
  end
end
