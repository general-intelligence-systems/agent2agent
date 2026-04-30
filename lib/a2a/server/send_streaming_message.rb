# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Server
    class SendStreamingMessage
      def call(env)
        env["a2a.result"] = Schema["Stream Response"].new({})
      end
    end
  end
end
