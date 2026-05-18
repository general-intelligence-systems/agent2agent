#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "a2a"

client = A2A::Client.new("http://localhost:9292", binding: :rest)

created = client.send_message(
  message: {
    message_id: "msg-1",
    role: "ROLE_USER",
    parts: [{ text: "Hello" }]
  }
)
task_id = created.task["id"]

result = client.get_task(id: task_id)

pp result.to_h
