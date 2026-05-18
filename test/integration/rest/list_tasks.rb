#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "a2a"

client = A2A::Client.new("http://localhost:9292", binding: :rest)

created = client.send_message(
  "messageId" => "msg-1", "role" => "ROLE_USER", "parts" => [{ "text" => "Hello" }]
)
context_id = created.task["contextId"]

result = client.list_tasks("contextId" => context_id)

pp result.to_h
