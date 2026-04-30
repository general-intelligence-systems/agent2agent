# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Server
    class GetExtendedAgentCard
      def call(env)
        card = env["a2a.agent_card"] || {}
        env["a2a.result"] = Schema["Agent Card"].new(card)
      end
    end
  end
end
