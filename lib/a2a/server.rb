# frozen_string_literal: true

require "bundler/setup"
require "a2a"

require "a2a/server/env"
require "a2a/server/well_known"
require "a2a/server/triage"
require "a2a/server/dispatcher"

module A2A
  # Rack application that exposes an A2A-compliant agent server.
  #
  # Composes a single linear middleware stack. Each middleware checks the
  # request path and either handles the request or passes it downstream:
  #
  #   Env               → injects shared context into the env
  #   WellKnown         → serves /.well-known/agent-card.json
  #   Bindings::Grpc    → /grpc (reserved) → 501 Not Implemented
  #   Bindings::Rest    → /rest (HTTP+JSON/REST)
  #   Bindings::JsonRpc → everything else (JSON-RPC 2.0)
  #   Triage            → resolves the target operation
  #   Dispatcher        → invokes the registered handler
  #
  # Usage:
  #
  #   agent = A2A::Agent.new do
  #     on "SendMessage" do
  #       respond_with -> (env) {
  #         A2A::Schema["Send Message Response"].new({})
  #       }
  #     end
  #   end
  #
  #   app = A2A::Server.new(agent_card: { "name" => "My Agent", ... })
  #   app.register(agent)
  #
  #   run app
  #
  class Server
    def initialize(agent_card: {})
      @agent_card = agent_card
      @dispatcher = Dispatcher.new
      @app        = build_app
    end

    # Register an Agent or a plain handler on the internal dispatcher.
    #
    # Accepts either:
    #   - An Agent (responds to #handlers) — registers all its handlers
    #   - A plain handler (responds to #operations and #call)
    #
    def register(handler)
      if handler.respond_to?(:handlers)
        handler.handlers.each { |h| @dispatcher.register(h) }
      else
        @dispatcher.register(handler)
      end
    end

    def call(env)
      @app.call(env)
    end

    private

      def build_app
        require "a2a/server/bindings/grpc"
        require "a2a/server/bindings/json_rpc"
        require "a2a/server/bindings/rest"

        agent_card = @agent_card
        dispatcher = @dispatcher

        Rack::Builder.app do
          use A2A::Server::Env, agent_card: agent_card
          use A2A::Server::WellKnown
          use A2A::Server::Bindings::Grpc,    path_prefix: "/grpc"
          use A2A::Server::Bindings::Rest,    path_prefix: "/rest"
          use A2A::Server::Bindings::JsonRpc, path_prefix: "/"
          use A2A::Server::Triage
          run dispatcher
        end
      end
  end
end
