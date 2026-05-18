# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Middleware
    # Applies history truncation to the task loaded by FetchTask.
    #
    # Accepts an optional server-side max cap. When provided, the effective
    # history length is the *minimum* of the client-requested value and the
    # server cap. When the client doesn't specify a history_length, the
    # server cap is used as the default.
    #
    # Sets `env["a2a.history"]`:
    #   - `nil` when the effective length is 0 (exclude history)
    #   - truncated array when > 0
    #   - full history when no cap is configured and the client didn't ask
    #
    # Should be placed after FetchTask in the middleware stack so that
    # `env["a2a.task"]` is available.
    #
    # Usage:
    #
    #   # Server-side cap of 20 entries:
    #   on "GetTask" do
    #     use A2A::Middleware::FetchTask, store: sqlite_store
    #     use A2A::Middleware::LimitHistoryLength, 20
    #     respond_with -> (env) {
    #       task = env["a2a.task"]
    #       history = env["a2a.history"]
    #       # ...
    #     }
    #   end
    #
    #   # No server-side cap (honours client request only):
    #   on "GetTask" do
    #     use A2A::Middleware::FetchTask, store: sqlite_store
    #     use A2A::Middleware::LimitHistoryLength
    #     respond_with -> (env) { ... }
    #   end
    #
    class LimitHistoryLength
      def initialize(app, max = nil)
        @app = app
        @max = max
      end

      def call(env)
        request = env["a2a.request"]
        task    = env["a2a.task"]
        history = task ? task[:history] : nil

        limit = nil

        if request.respond_to?(:history_length) && request.history_length
          limit = request.history_length.to_i
        end

        if @max
          limit = limit ? [limit, @max].min : @max
        end

        if limit
          history = if limit == 0
            nil
          else
            history&.last(limit)
          end
        end

        env["a2a.history"] = history

        @app.call(env)
      end
    end
  end
end

test do
  describe "A2A::Middleware::LimitHistoryLength" do
    it "passes full history when no max and no client history_length" do
      request = Object.new
      request.define_singleton_method(:history_length) { nil }

      history = [{ "role" => "user" }, { "role" => "agent" }, { "role" => "user" }]
      task = { history: history }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should == history
    end

    it "returns nil when client requests history_length 0" do
      request = Object.new
      request.define_singleton_method(:history_length) { 0 }

      task = { history: [{ "role" => "user" }] }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should.be.nil
    end

    it "truncates history to the client-requested length" do
      request = Object.new
      request.define_singleton_method(:history_length) { 2 }

      history = [{ "m" => 1 }, { "m" => 2 }, { "m" => 3 }]
      task = { history: history }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should == [{ "m" => 2 }, { "m" => 3 }]
    end

    it "uses server max when client does not specify history_length" do
      request = Object.new
      request.define_singleton_method(:history_length) { nil }

      history = [{ "m" => 1 }, { "m" => 2 }, { "m" => 3 }]
      task = { history: history }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 2)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should == [{ "m" => 2 }, { "m" => 3 }]
    end

    it "caps client request to the server max" do
      request = Object.new
      request.define_singleton_method(:history_length) { 50 }

      history = (1..10).map { |i| { "m" => i } }
      task = { history: history }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 3)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should == [{ "m" => 8 }, { "m" => 9 }, { "m" => 10 }]
    end

    it "allows client request smaller than server max" do
      request = Object.new
      request.define_singleton_method(:history_length) { 1 }

      history = [{ "m" => 1 }, { "m" => 2 }, { "m" => 3 }]
      task = { history: history }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 10)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should == [{ "m" => 3 }]
    end

    it "handles string history_length values" do
      request = Object.new
      request.define_singleton_method(:history_length) { "1" }

      history = [{ "m" => 1 }, { "m" => 2 }]
      task = { history: history }

      downstream = -> (env) { env["a2a.history"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream)
      env = { "a2a.request" => request, "a2a.task" => task }

      result = mw.call(env)
      result.should == [{ "m" => 2 }]
    end
  end
end
