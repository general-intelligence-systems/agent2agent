#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "a2a"

client = A2A::Client.new("http://localhost:9292", binding: :rest)

created = client.send_message(
  "messageId" => "msg-1", "role" => "ROLE_USER", "parts" => [{ "text" => "Hello" }]
)
task_id = created.task["id"]

config = client.create_task_push_notification_config(
  "taskId" => task_id,
  "url" => "https://example.com/webhook"
)
config_id = config.id

result = client.delete_task_push_notification_config("id" => config_id, "taskId" => task_id)

pp result
