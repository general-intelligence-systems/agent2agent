# frozen_string_literal: true

require "bundler/setup"
require "a2a"

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

require "a2a/bindings/json_rpc"
require "a2a/bindings/rest"

module A2A
  # Rack application that exposes an A2A-compliant agent server.
  #
  # Composes a middleware stack:
  #
  #   Server (agent card, env setup)
  #     → Bindings::Rest  (outer — matches HTTP routes)
  #       → Bindings::JsonRpc (inner — handles JSON-RPC envelope)
  #         → Operation middlewares (one per A2A operation)
  #           → inner app (user's agent logic)
  #
  # The bindings parse the protocol envelope, set env["a2a.operation"]
  # and env["a2a.params"], then call downstream. Operation middlewares
  # check env["a2a.operation"], set env["a2a.result"] with a
  # Schema::Definition, and continue. The binding reads env["a2a.result"]
  # and formats the protocol response.
  #
  #   app = A2A::Server.new(agent_card: card)
  #   run app
  #
  class Server
    OPERATIONS = [
      SendMessage,
      SendStreamingMessage,
      GetTask,
      ListTasks,
      CancelTask,
      SubscribeToTask,
      CreateTaskPushNotificationConfig,
      GetTaskPushNotificationConfig,
      ListTaskPushNotificationConfigs,
      DeleteTaskPushNotificationConfig,
      GetExtendedAgentCard,
    ].freeze

    def initialize(app = nil, agent_card: {}, store: TaskStore.new)
      @agent_card = agent_card
      @store = store

      inner = app || default_app

      # Wrap with operation middlewares (innermost layer)
      stack = OPERATIONS.reduce(inner) { |s, klass| klass.new(s) }

      # Wrap with protocol bindings (outermost layer)
      stack = Bindings::JsonRpc.new(stack)
      stack = Bindings::Rest.new(stack)

      @stack = stack
    end

    def call(env)
      env["a2a.store"] = @store
      env["a2a.agent_card"] = @agent_card

      if env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"] == "/.well-known/agent-card.json"
        serve_agent_card
      else
        @stack.call(env)
      end
    end

    private

      def default_app
        ->(env) { [404, { "content-type" => "text/plain" }, ["Not found"]] }
      end

      def serve_agent_card
        body = @agent_card.is_a?(Hash) ? @agent_card : @agent_card.to_h
        [200, { "content-type" => "application/json" }, [JSON.generate(body)]]
      end
  end
end
