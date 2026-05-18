#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "a2a"

client = A2A::Client.new("http://localhost:9292", binding: :rest)

client.send_streaming_message(
  message: {
    message_id: "msg-1",
    role: "ROLE_USER",
    parts: [{ text: "Stream me" }]
  }
) do |chunk, env|
  puts chunk
end
