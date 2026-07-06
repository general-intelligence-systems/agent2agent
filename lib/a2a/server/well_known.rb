# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    # Rack middleware that serves the agent card at the well-known
    # discovery path. All other requests pass through untouched.
    #
    class WellKnown
      PATH = "/.well-known/agent-card.json"

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless env["PATH_INFO"] == PATH

        card = env["a2a.agent_card"] || {}
        body = card.is_a?(Hash) ? card : card.to_h
        [200, { "content-type" => "application/json" }, [JSON.generate(body)]]
      end
    end
  end
end
