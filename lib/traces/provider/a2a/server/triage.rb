# frozen_string_literal: true

require_relative "../../../../a2a/server/triage"
require "traces/provider"

Traces::Provider(A2A::Server::Triage) do
  def call(env)
    Traces.trace("a2a.server.triage.call") do |span|
      super.tap do
        if op = env["a2a.operation"]
          span["a2a.operation"] = op
        end

        if proto_op = env["a2a.proto_operation"]
          span["a2a.proto_operation"] = proto_op.name
        end
      end
    end
  end
end
