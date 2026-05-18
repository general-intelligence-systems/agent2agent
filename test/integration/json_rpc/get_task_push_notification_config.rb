#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "a2a"

client = A2A::Client.new("http://localhost:9292")

created = client.send_message(
  message: {
    message_id: "msg-1",
    role: "ROLE_USER",
    parts: [{ text: "Hello" }]
  }
)
task_id = created.task.id

config = client.create_task_push_notification_config(
  task_id: task_id,
  url: "https://example.com/webhook"
)
config_id = config.id

result = client.get_task_push_notification_config(
  id: config_id,
  task_id: task_id
)

pp result.to_h
