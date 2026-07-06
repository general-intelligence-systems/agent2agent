# frozen_string_literal: true

require "a2a"
require "a2a/agent"
require "a2a/protocol/protobuf"
require "a2a/protocol/json_schema"

module A2A
  module TestHelpers
    # Returns a stub agent server that handles all A2A operations with
    # minimal valid responses. Useful for integration tests that
    # need a working server without real business logic.
    def self.stub_agent(agent_card: {})
      schema = A2A::Protocol::JsonSchema

      A2A.agent(agent_card: agent_card) do |env|
        case env["a2a.operation"]
        in "SendMessage"
          schema["Send Message Response"].new({})
        in "SendStreamingMessage" | "SubscribeToTask"
          schema["Stream Response"].new({})
        in "GetTask"
          schema["Task"].new(
            "id"        => "test-id",
            "contextId" => "ctx-1",
            "status"    => { "state" => "TASK_STATE_COMPLETED", "timestamp" => "2025-01-01T00:00:00Z" }
          )
        in "CancelTask"
          schema["Task"].new(
            "id"        => "test-id",
            "contextId" => "ctx-1",
            "status"    => { "state" => "TASK_STATE_CANCELED", "timestamp" => "2025-01-01T00:00:00Z" }
          )
        in "ListTasks"
          schema["List Tasks Response"].new({})
        in "CreateTaskPushNotificationConfig" | "GetTaskPushNotificationConfig"
          schema["Task Push Notification Config"].new("url" => "http://example.com")
        in "ListTaskPushNotificationConfigs"
          schema["List Task Push Notification Configs Response"].new({})
        in "GetExtendedAgentCard"
          schema["Agent Card"].new("name" => "Test", "version" => "1.0")
        in "DeleteTaskPushNotificationConfig"
          nil
        end
      end
    end
  end
end
