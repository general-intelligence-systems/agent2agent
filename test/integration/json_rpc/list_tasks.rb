#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "a2a"

client = A2A::Client.new("http://localhost:9292")

created = client.send_message(
  message: { "messageId" => "msg-1", "role" => "ROLE_USER", "parts" => [{ "text" => "Hello" }] }
)
context_id = created.task.context_id

result = client.list_tasks(context_id: context_id)

pp result.to_h
