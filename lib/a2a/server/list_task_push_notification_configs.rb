# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Server
    class ListTaskPushNotificationConfigs
      def call(env)
        env["a2a.result"] = Schema["List Task Push Notification Configs Response"].new({})
      end
    end
  end
end
