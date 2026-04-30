# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Server
    class DeleteTaskPushNotificationConfig
      def call(env)
        env["a2a.result"] = nil # google.protobuf.Empty
      end
    end
  end
end
