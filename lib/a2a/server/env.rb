# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    # Rack middleware that injects shared A2A context into the env.
    #
    # Sets env["a2a.agent_card"] so downstream middleware and handlers
    # can access it without coupling to any particular configuration
    # mechanism.
    #
    class Env
      def initialize(app, agent_card: {})
        @app = app
        @agent_card = agent_card
      end

      def call(env)
        env["a2a.agent_card"] = @agent_card
        @app.call(env)
      end
    end
  end
end
