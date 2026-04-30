# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Server
    class GetTaskPushNotificationConfig
      def call(env)
        env["a2a.result"] = Schema["Task Push Notification Config"].new({})
      end
    end
  end
end
