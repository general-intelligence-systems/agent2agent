# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Middleware
    # Resolves the effective history length limit and sets
    # `env["a2a.history_length"]` to an integer.
    #
    # The server max is required. The effective limit is the *minimum*
    # of the client-requested value and the server cap. When the client
    # doesn't specify a history_length, the server cap is used.
    #
    # `env["a2a.history_length"]` is always an Integer (0..max).
    # The handler applies it unconditionally:
    #
    #   result["history"] = task[:history]&.last(limit)
    #
    # Usage:
    #
    #   on "GetTask" do
    #     use A2A::Middleware::FetchTaskOrRaise, store: sqlite_store
    #     use A2A::Middleware::LimitHistoryLength, 20
    #     respond_with -> (env) {
    #       task  = env["a2a.task"]
    #       limit = env["a2a.history_length"]
    #       # ...
    #       result["history"] = task[:history]&.last(limit)
    #     }
    #   end
    #
    class LimitHistoryLength
      def initialize(app, max)
        @app = app
        @max = max
      end

      def call(env)
        request = env["a2a.request"]
        limit = @max

        if request.respond_to?(:history_length) && request.history_length
          limit = [request.history_length.to_i, @max].min
        end

        env["a2a.history_length"] = limit

        @app.call(env)
      end
    end
  end
end

__END__
  describe "A2A::Middleware::LimitHistoryLength" do
    it "defaults to server max when client does not specify" do
      request = Object.new
      request.define_singleton_method(:history_length) { nil }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 20)
      env = { "a2a.request" => request }

      mw.call(env).should == 20
    end

    it "uses client value when smaller than max" do
      request = Object.new
      request.define_singleton_method(:history_length) { 5 }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 20)
      env = { "a2a.request" => request }

      mw.call(env).should == 5
    end

    it "caps client value to server max" do
      request = Object.new
      request.define_singleton_method(:history_length) { 100 }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 20)
      env = { "a2a.request" => request }

      mw.call(env).should == 20
    end

    it "returns 0 when client requests 0" do
      request = Object.new
      request.define_singleton_method(:history_length) { 0 }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 20)
      env = { "a2a.request" => request }

      mw.call(env).should == 0
    end

    it "handles string values" do
      request = Object.new
      request.define_singleton_method(:history_length) { "3" }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 20)
      env = { "a2a.request" => request }

      mw.call(env).should == 3
    end

    it "always returns an integer" do
      request = Object.new
      request.define_singleton_method(:history_length) { nil }

      downstream = -> (env) { env["a2a.history_length"] }
      mw = A2A::Middleware::LimitHistoryLength.new(downstream, 10)
      env = { "a2a.request" => request }

      mw.call(env).should.be.kind_of(Integer)
    end
  end
