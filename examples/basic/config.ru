# frozen_string_literal: true

# Echo Agent — A2A Rack entry point
#
# Run with:
#   cd example && bundle exec falcon serve --bind http://0.0.0.0:9292
#
# Test with:
#   curl http://localhost:9292/.well-known/agent-card.json
#
#   curl -X POST http://localhost:9292/a2a \
#     -H "Content-Type: application/json" \
#     -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{}}'

require "bundler/setup"
require "a2a"
require "console"

agent_card = {
  "name"        => "Echo Agent",
  "description" => "A simple echo agent that repeats your message.",
  "url"         => "http://localhost:9292",
  "version"     => "1.0.0",
}

agent = A2A::Agent.new do
  on "SendMessage" do |request|
    respond A2A::Schema["Send Message Response"].new({})
  end

  on "GetTask" do |request|
    respond A2A::Schema["Task"].new({})
  end
end

app = A2A::Server.new(agent_card: agent_card)
app.register(agent)

Console.info(self) { "Echo Agent starting..." }
Console.info(self) { "Agent card: #{agent_card["name"]}" }

run app
