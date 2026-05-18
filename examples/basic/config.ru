# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "console"
require "yaml"

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

agent = A2A::Agent.new do
  on "SendMessage" do
    respond_with -> (env) {
      A2A::Schema["Send Message Response"].new({})
    }
  end

  on "GetTask" do
    respond_with -> (env) {
      A2A::Schema["Task"].new({})
    }
  end
end

app = A2A::Server.new(agent_card: agent_card)
app.register(agent)

Console.info(self) { "Echo Agent starting..." }
Console.info(self) { "Agent card: #{agent_card["name"]}" }

run app
