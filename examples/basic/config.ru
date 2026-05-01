# frozen_string_literal: true

require "bundler/setup"
require "scampi"
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
