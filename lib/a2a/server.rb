# frozen_string_literal: true

require "bundler/setup"
require "a2a"

require "a2a/server/env"

require "a2a/server/send_message"
require "a2a/server/send_streaming_message"
require "a2a/server/get_task"
require "a2a/server/list_tasks"
require "a2a/server/cancel_task"
require "a2a/server/subscribe_to_task"
require "a2a/server/create_task_push_notification_config"
require "a2a/server/get_task_push_notification_config"
require "a2a/server/list_task_push_notification_configs"
require "a2a/server/delete_task_push_notification_config"
require "a2a/server/get_extended_agent_card"

require "a2a/server/triage"
require "a2a/server/dispatcher"

require "a2a/bindings/json_rpc"
require "a2a/bindings/rest"

module A2A
  # Rack application that exposes an A2A-compliant agent server.
  #
  # Uses Rack::Builder to compose two separate middleware stacks,
  # one for each protocol binding:
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
  # The bindings strip/wrap protocol envelopes. Triage resolves the
  # A2A operation and builds a Schema::Definition request. Dispatcher
  # calls the matching operation handler, then continues the chain.
  #
  #   run A2A::Server
  #
  module Server
    @app = Rack::Builder.app do
      use A2A::Server::Env

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
        use A2A::Server::Dispatcher
        run ->(env) { [200, {}, []] }
      end

      map "/" do
        use A2A::Bindings::Rest
        use A2A::Server::Triage
        use A2A::Server::Dispatcher
        run ->(env) { [200, {}, []] }
      end
    end

    def self.call(env)
      @app.call(env)
    end
  end
end
