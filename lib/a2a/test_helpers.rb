# frozen_string_literal: true

require "a2a"
require "a2a/agent"
require "a2a/proto"
require "a2a/schema"

module A2A
  module TestHelpers
    # Returns a stub agent that handles all A2A operations with
    # minimal valid responses. Useful for integration tests that
    # need a working server without real business logic.
    def self.stub_agent
      Agent.new do
        on "SendMessage" do
          respond_with -> (env) {
            A2A::Schema["Send Message Response"].new({})
          }
        end

        on "SendStreamingMessage" do
          respond_with -> (env) {
            A2A::Schema["Stream Response"].new({})
          }
        end

        on "GetTask" do
          respond_with -> (env) {
            A2A::Schema["Task"].new(
              "id"        => "test-id",
              "contextId" => "ctx-1",
              "status"    => { "state" => "TASK_STATE_COMPLETED", "timestamp" => "2025-01-01T00:00:00Z" }
            )
          }
        end

        on "ListTasks" do
          respond_with -> (env) {
            A2A::Schema["List Tasks Response"].new({})
          }
        end

        on "CancelTask" do
          respond_with -> (env) {
            A2A::Schema["Task"].new(
              "id"        => "test-id",
              "contextId" => "ctx-1",
              "status"    => { "state" => "TASK_STATE_CANCELED", "timestamp" => "2025-01-01T00:00:00Z" }
            )
          }
        end

        on "SubscribeToTask" do
          respond_with -> (env) {
            A2A::Schema["Stream Response"].new({})
          }
        end

        on "CreateTaskPushNotificationConfig" do
          respond_with -> (env) {
            A2A::Schema["Task Push Notification Config"].new("url" => "http://example.com")
          }
        end

        on "GetTaskPushNotificationConfig" do
          respond_with -> (env) {
            A2A::Schema["Task Push Notification Config"].new("url" => "http://example.com")
          }
        end

        on "ListTaskPushNotificationConfigs" do
          respond_with -> (env) {
            A2A::Schema["List Task Push Notification Configs Response"].new({})
          }
        end

        on "GetExtendedAgentCard" do
          respond_with -> (env) {
            A2A::Schema["Agent Card"].new("name" => "Test", "version" => "1.0")
          }
        end

        on "DeleteTaskPushNotificationConfig" do
          respond_with -> (env) { nil }
        end
      end
    end
  end
end
