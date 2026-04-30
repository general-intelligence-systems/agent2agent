# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Server
    class ListTasks
      def call(env)
        env["a2a.result"] = Schema["List Tasks Response"].new({})
      end
    end
  end
end
