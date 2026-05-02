# frozen_string_literal: true

require_relative "../../../../a2a/bindings/json_rpc"
require "traces/provider"

Traces::Provider(A2A::Bindings::JsonRpc) do
  def call(env)
    Traces.trace("a2a.bindings.json_rpc.call") do |span|
      super.tap do |status, headers, body|
        span["http.status_code"] = status

        if method = env["a2a.json_rpc_method"]
          span["rpc.method"] = method
        end

        if id = env["a2a.json_rpc_id"]
          span["rpc.jsonrpc.request_id"] = id.to_s
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
