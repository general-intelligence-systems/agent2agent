# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    class DeleteTaskPushNotificationConfig
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless env["a2a.operation"] == "DeleteTaskPushNotificationConfig"

        env["a2a.result"] = nil # google.protobuf.Empty
        @app.call(env)
      end
    end
  end
end
