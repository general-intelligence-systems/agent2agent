#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "a2a"

client = A2A::Client.new("http://localhost:9292")

result = client.send_message(
  message: { "messageId" => "msg-1", "role" => "ROLE_USER", "parts" => [{ "text" => "Hello" }] }
)

pp result.to_h
