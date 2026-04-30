# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    class GetExtendedAgentCard
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless env["a2a.operation"] == "GetExtendedAgentCard"

        card = env["a2a.agent_card"] || {}
        env["a2a.result"] = Schema["Agent Card"].new(card)
        @app.call(env)
      end
    end
  end
end
