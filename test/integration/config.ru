# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/sse"
require "a2a/store"
require "a2a/test_helpers"
require "console"
require "yaml"

agent_card = YAML.safe_load_file(File.join(__dir__, "agent_card.yml"))

app = A2A::Server.new(agent_card: agent_card)
app.register(A2A::TestHelpers.stub_agent)

run app
