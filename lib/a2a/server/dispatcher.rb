# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Server
    # Rack middleware that dispatches to the correct A2A operation handler.
    #
    # Reads env["a2a.operation"] (set by Triage), looks up the matching
    # handler from the HANDLERS registry, calls it to set env["a2a.result"],
    # then continues the middleware chain via @app.call(env).
    #
    # Handlers are plain objects with a #call(env) method — they are NOT
    # middleware. They set env["a2a.result"] and return.
    #
    class Dispatcher
      HANDLERS = {
        "SendMessage"                       => Server::SendMessage,
        "SendStreamingMessage"              => Server::SendStreamingMessage,
        "GetTask"                           => Server::GetTask,
        "ListTasks"                         => Server::ListTasks,
        "CancelTask"                        => Server::CancelTask,
        "SubscribeToTask"                   => Server::SubscribeToTask,
        "CreateTaskPushNotificationConfig"  => Server::CreateTaskPushNotificationConfig,
        "GetTaskPushNotificationConfig"     => Server::GetTaskPushNotificationConfig,
        "ListTaskPushNotificationConfigs"   => Server::ListTaskPushNotificationConfigs,
        "DeleteTaskPushNotificationConfig"  => Server::DeleteTaskPushNotificationConfig,
        "GetExtendedAgentCard"              => Server::GetExtendedAgentCard,
      }.freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        operation = env["a2a.operation"]

        if operation && (handler_class = HANDLERS[operation])
          handler_class.new.call(env)
        end

        @app.call(env)
      end
    end
  end
end
