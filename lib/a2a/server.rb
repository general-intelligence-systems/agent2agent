# frozen_string_literal: true

require "bundler/setup"
require "a2a"

require "a2a/server/env"
require "a2a/server/well_known"
require "a2a/server/triage"

module A2A
  # Rack application that exposes an A2A-compliant agent server.
  #
  # Composes a single linear middleware stack. Each middleware checks the
  # request path and either handles the request or passes it downstream:
  #
  #   Env                 → injects shared context into the env
  #   WellKnown           → serves /.well-known/agent-card.json
  #   Bindings::Grpc      → /grpc (reserved) → 501 Not Implemented
  #   Bindings::Rest      → /rest (HTTP+JSON/REST)
  #   Bindings::JsonRpc   → everything else (JSON-RPC 2.0)
  #   SSEStream           → offers env["a2a.stream"] to the agent
  #   Triage              → resolves the target operation
  #   ExtractMessage      → sets env["a2a.message"] when a message is present
  #   LimitHistoryLength  → sets env["a2a.history_length"]
  #   LimitPaginationSize → sets env["a2a.page_size"]
  #   Agent               → the terminal app (your block)
  #
  # The block is the terminal rack app — it is executed at the end of
  # the stack, wrapped in the A2A::Agent error boundary. Usage
  # (A2A.agent is a shorthand for this):
  #
  #   app = A2A::Server.new(agent_card: { "name" => "My Agent", ... }) do |env|
  #     case env["a2a.operation"]
  #     in "SendMessage"
  #       A2A::Protocol::JsonSchema["Send Message Response"].new({})
  #     end
  #   end
  #
  #   run app
  #
  class Server
    def initialize(agent_card: {}, history_length: 100, page_size: 100, &block)
      raise ArgumentError, "Server requires a block" unless block

      @agent_card     = agent_card
      @agent          = Agent.new(&block)
      @history_length = history_length
      @page_size      = page_size
      @app            = build_app
    end

    def call(env)
      @app.call(env)
    end

    private

      def build_app
        require "a2a/server/bindings/grpc"
        require "a2a/server/bindings/json_rpc"
        require "a2a/server/bindings/rest"
        require "a2a/server/middleware"

        agent_card     = @agent_card
        agent          = @agent
        history_length = @history_length
        page_size      = @page_size

        Rack::Builder.app do
          use A2A::Server::Env, agent_card: agent_card
          use A2A::Server::WellKnown
          use A2A::Server::Bindings::Grpc,    path_prefix: "/grpc"
          use A2A::Server::Bindings::Rest,    path_prefix: "/rest"
          use A2A::Server::Bindings::JsonRpc, path_prefix: "/"
          use A2A::Server::Middleware::SSEStream
          use A2A::Server::Triage
          use A2A::Server::Middleware::ExtractMessage
          use A2A::Server::Middleware::LimitHistoryLength, history_length
          use A2A::Server::Middleware::LimitPaginationSize, page_size
          run agent
        end
      end
  end
end
