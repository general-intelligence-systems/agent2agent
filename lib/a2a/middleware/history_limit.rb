# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Middleware
    class HistoryLimit
      def initialize(app, max = 100)
        @app = app
        @max = max
      end

      def call(env)
        request = env["a2a.request"]
        hl = request.history_length
        if hl
          hl = hl.to_i
          hl = 0 if hl < 0
          hl = @max if hl > @max
        end
        env["a2a.history_length"] = hl
        @app.call(env)
      end
    end
  end
end

test do
  describe "A2A::Middleware::HistoryLimit" do
    it "passes nil through when history_length not set" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new({})
      env = { "a2a.request" => request }

      mw = A2A::Middleware::HistoryLimit.new(app, 100)
      result = mw.call(env)
      result["a2a.history_length"].should == nil
    end

    it "clamps history_length to max" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new(history_length: 200)
      env = { "a2a.request" => request }

      mw = A2A::Middleware::HistoryLimit.new(app, 100)
      result = mw.call(env)
      result["a2a.history_length"].should == 100
    end

    it "passes through valid history_length" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new(history_length: 10)
      env = { "a2a.request" => request }

      mw = A2A::Middleware::HistoryLimit.new(app, 100)
      result = mw.call(env)
      result["a2a.history_length"].should == 10
    end

    it "clamps negative to 0" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new(history_length: -5)
      env = { "a2a.request" => request }

      mw = A2A::Middleware::HistoryLimit.new(app, 100)
      result = mw.call(env)
      result["a2a.history_length"].should == 0
    end

    it "allows 0 (means omit history)" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new(history_length: 0)
      env = { "a2a.request" => request }

      mw = A2A::Middleware::HistoryLimit.new(app, 100)
      result = mw.call(env)
      result["a2a.history_length"].should == 0
    end

    it "uses custom max" do
      app = -> (env) { env }
      request = A2A::Schema["List Tasks Request"].new(history_length: 30)
      env = { "a2a.request" => request }

      mw = A2A::Middleware::HistoryLimit.new(app, 20)
      result = mw.call(env)
      result["a2a.history_length"].should == 20
    end
  end
end
