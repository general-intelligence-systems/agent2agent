# frozen_string_literal: true

# Example A2A server using Falcon.
#
# Run with:
#   cd example && bundle exec falcon serve -b http://localhost:9292
#
# Test with:
#   curl http://localhost:9292/.well-known/agent-card.json
#
#   curl -X POST http://localhost:9292/ \
#     -H "Content-Type: application/json" \
#     -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{}}'

require "bundler/setup"
require "a2a"

agent_card = {
  "name"        => "Echo Agent",
  "description" => "A simple echo agent that repeats your message.",
  "url"         => "http://localhost:9292",
  "version"     => "1.0.0",
}

app = A2A::Server.new(agent_card: agent_card)

run app
