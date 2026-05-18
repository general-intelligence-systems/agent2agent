#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "a2a"

client = A2A::Client.new("http://localhost:9292")

begin
  result = client.get_extended_agent_card
  pp result.to_h
rescue => e
  # Expected — most agents don't support this
  puts "Expected error: #{e.message}"
end
