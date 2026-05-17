# frozen_string_literal: true

require "bundler/setup"
require "a2a"

require "a2a/server/env"
require "a2a/server/triage"
require "a2a/server/dispatcher"

module A2A
  # Rack application that exposes an A2A-compliant agent server.
  #
  # Composes two separate middleware stacks, one for each protocol binding:
  #
  #   /.well-known/agent-card.json
  #     → Env → serve agent card
  #
  #   /a2a  (JSON-RPC 2.0)
  #     → Env → Bindings::JsonRpc → Triage → Dispatcher
  #
  #   /     (HTTP+JSON/REST)
  #     → Env → Bindings::Rest → Triage → Dispatcher
  #
  # Usage:
  #
  #   agent = A2A::Agent.new do
  #     on "SendMessage" do |request|
  #       respond A2A::Schema["Send Message Response"].new({})
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
        require "a2a/bindings/json_rpc"
        require "a2a/bindings/rest"

        agent_card = @agent_card
        dispatcher = @dispatcher

        Rack::Builder.app do
          use A2A::Server::Env, agent_card: agent_card

          map "/.well-known/agent-card.json" do
            run ->(env) {
              card = env["a2a.agent_card"] || {}
              body = card.is_a?(Hash) ? card : card.to_h
              [200, { "content-type" => "application/json" }, [JSON.generate(body)]]
            }
          end

          map "/a2a" do
            use A2A::Bindings::JsonRpc
            use A2A::Server::Triage
            run dispatcher
          end

          map "/" do
            use A2A::Bindings::Rest
            use A2A::Server::Triage
            run dispatcher
          end
        end
      end
  end
end
