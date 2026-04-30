# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  class Server
    class GetTask
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless env["a2a.operation"] == "GetTask"

        env["a2a.result"] = Schema["Task"].new({})
        @app.call(env)
      end
    end
  end
end
