# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    class SendStreamingMessage
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless env["a2a.operation"] == "SendStreamingMessage"

        env["a2a.result"] = Schema["Stream Response"].new({})
        @app.call(env)
      end
    end
  end
end
