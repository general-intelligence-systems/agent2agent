# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Middleware
    # Resolves the effective history length limit from the client request
    # and an optional server-side cap, setting `env["a2a.history_length"]`.
    #
    # The effective limit is the *minimum* of the client-requested value
    # and the server cap. When the client doesn't specify a history_length,
    # the server cap is used as the default.
    #
    # Sets `env["a2a.history_length"]`:
    #   - `nil`  — no limit (include full history)
    #   - `0`    — exclude history entirely
    #   - `N`    — truncate to last N entries
    #
    # The handler is responsible for applying the limit to the actual
    # history data. This middleware only resolves the value.
    #
    # Usage:
    #
    #   # Server-side cap of 20 entries:
    #   on "GetTask" do
    #     use A2A::Middleware::FetchTask, store: sqlite_store
    #     use A2A::Middleware::LimitHistoryLength, 20
    #     respond_with -> (env) {
    #       task  = env["a2a.task"]
    #       limit = env["a2a.history_length"]
    #       # apply limit to task[:history] ...
    #     }
    #   end
    #
    #   # No server-side cap (honours client request only):
    #   on "ListTasks" do
    #     use A2A::Middleware::LimitHistoryLength
    #     respond_with -> (env) {
    #       limit = env["a2a.history_length"]
    #       # apply limit to each task's history ...
    #     }
    #   end
    #
    class LimitHistoryLength
      def initialize(app, max = nil)
        @app = app
        @max = max
      end

      def call(env)
        request = env["a2a.request"]

        limit = nil

        if request.respond_to?(:history_length) && request.history_length
          limit = request.history_length.to_i
        end

        if @max
          limit = limit ? [limit, @max].min : @max
        end

        env["a2a.history_length"] = limit

        @app.call(env)
      end
    end
  end
end

test do
  describe "A2A::Middleware::LimitHistoryLength" do
    it "sets nil when no max and no client history_length" do
      request = Object.new
      request.define_singleton_method(:history_length) { nil }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should.be.nil
    end

    it "returns 0 when client requests history_length 0" do
      request = Object.new
      request.define_singleton_method(:history_length) { 0 }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 0
    end

    it "returns client-requested length" do
      request = Object.new
      request.define_singleton_method(:history_length) { 2 }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 2
    end

    it "uses server max when client does not specify history_length" do
      request = Object.new
      request.define_singleton_method(:history_length) { nil }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 20)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 20
    end

    it "caps client request to the server max" do
      request = Object.new
      request.define_singleton_method(:history_length) { 50 }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 3)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 3
    end

    it "allows client request smaller than server max" do
      request = Object.new
      request.define_singleton_method(:history_length) { 1 }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 10)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 1
    end

    it "handles string history_length values" do
      request = Object.new
      request.define_singleton_method(:history_length) { "5" }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream)
      env = { "a2a.request" => request }

      result = mw.call(env)
      result.should == 5
    end
  end
end
