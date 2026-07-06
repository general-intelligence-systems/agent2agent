# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "console"
require "yaml"

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

agent = A2A.agent(agent_card: agent_card) do |env|
  case env["a2a.operation"]
  in "SendMessage"
    A2A::Protocol::JsonSchema["Send Message Response"].new({})
  in "GetTask"
    A2A::Protocol::JsonSchema["Task"].new({})
  end
end

Console.info(self) { "Echo Agent starting..." }
Console.info(self) { "Agent card: #{agent_card["name"]}" }

run agent
