# frozen_string_literal: true

require_relative "../../../a2a/agent"
require "traces/provider"

Traces::Provider(A2A::Agent) do
  def call(env)
    attributes = {
      "a2a.operation" => env["a2a.operation"],
    }

    Traces.trace("a2a.agent.call", attributes: attributes) do |span|
      super.tap do |result|
        if result.is_a?(A2A::Error)
          span["a2a.response_type"] = "error"
          span["a2a.error.code"]    = result.code
        elsif env["a2a.stream"].is_a?(A2A::Server::SSE::Stream)
          span["a2a.response_type"] = "stream"
        else
          span["a2a.response_type"] = "result"
        end
      end
    end
  end
end
